import Foundation
import OrderedCollections

extension Qs {
    /// A conservative threshold for scheduling the destruction of temporary deep graphs
    /// on the main thread (see `_decodeSyncCore` and `Utils.dropOnMainThread`).
    ///
    /// Rationale: some Apple Swift runtimes can recurse deeply while tearing down
    /// long single-key chains (e.g. `["p": ["p": ...]]`) which risks a `EXC_BAD_ACCESS`
    /// in a background thread. Handing the *final release* to the main thread avoids
    /// that destructor recursion in practice.
    private static let MAIN_DROP_THRESHOLD = 2500

    // MARK: - Public API (Sync)

    /// Decode a query `String` or a dictionary-like value into a `[String: Any]`.
    ///
    /// - Parameters:
    ///   - input: A query string, or a dictionary-shaped value (`[String: Any]`, `[String: Any?]`,
    ///            or `[AnyHashable: Any]`). Non-string keys are stringified.
    ///   - options: Decoder settings (limits, charset, list parsing rules, etc).
    ///
    /// - Returns: A plain `[String: Any]`. Insertion order of parsed keys is preserved.
    ///
    /// - Throws:
    ///   - An `NSError(domain: "Qs.decode")` if `input` has an unsupported type.
    ///   - `DecodeError` on limit/depth violations when `strictDepth` / `throwOnLimitExceeded`
    ///     are enabled.
    ///
    /// - Performance:
    ///   - Uses an iterative “bridge to Any” to avoid deep recursion when materializing the result.
    ///   - For extremely deep graphs, `_decodeSyncCore` may schedule the destruction of a temporary
    ///     graph on the main thread as a safety valve (see notes in that method).
    public static func decode(
        _ input: Any?,
        options: DecodeOptions = .init()
    ) throws -> [String: Any] {
        try _decodeSyncCore(input, options: options)
    }

    // MARK: - Public API (Async)

    /// Asynchronous decode that runs the heavy work on a background queue and returns
    /// a `DecodedMap` wrapper (so the result is Sendable).
    ///
    /// Use this when decoding may be costly (large query strings, very deep nesting)
    /// and you don’t want to block the caller’s executor.
    ///
    /// - Parameters:
    ///   - input: Same as `decode(_:options:)`.
    ///   - options: Same as `decode(_:options:)`.
    ///   - qos: Dispatch QoS for the background work (defaults to `.userInitiated`).
    ///
    /// - Returns: A `DecodedMap` (Sendable wrapper around `[String: Any]`).
    ///
    /// - Threading:
    ///   - Work is dispatched to a global `DispatchQueue` with the given QoS.
    ///   - The continuation resumes on *that* queue; choose `decodeAsyncOnMain` if you need
    ///     the returned dictionary on the main actor.
    ///
    /// - Note:
    ///   We box the non-Sendable arguments (`Any?`, `DecodeOptions`) with `_UnsafeSendable`
    ///   to satisfy strict concurrency checks; the decode work itself is isolated to the
    ///   background queue.
    public nonisolated static func decodeAsync(
        _ input: Any?,
        options: DecodeOptions = .init(),
        qos: DispatchQoS.QoSClass = .userInitiated
    ) async throws -> DecodedMap {
        try await withCheckedThrowingContinuation { cont in
            let inputBox = _UnsafeSendable(input)
            let optionsBox = _UnsafeSendable(options)

            DispatchQueue.global(qos: qos).async {
                do {
                    let dict = try _decodeSyncCore(inputBox.value, options: optionsBox.value)
                    cont.resume(returning: DecodedMap(dict))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Internal async helper that accepts *boxed* arguments.
    ///
    /// This exists so `decodeAsyncOnMain` can box on the main actor and hand the safe,
    /// boxed payload across threads without tripping strict concurrency checks.
    internal nonisolated static func decodeAsyncBoxed(
        _ input: _UnsafeSendable<Any?>,
        options: _UnsafeSendable<DecodeOptions>,
        qos: _UnsafeSendable<DispatchQoS.QoSClass> = _UnsafeSendable(.userInitiated)
    ) async throws -> DecodedMap {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: qos.value).async {
                do {
                    let dict = try _decodeSyncCore(input.value, options: options.value)
                    cont.resume(returning: DecodedMap(dict))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Core implementation

    /// Shared synchronous implementation used by both sync and async front-doors.
    ///
    /// Pipeline:
    /// 1. Validate input type (string or dictionary-like).
    /// 2. Parse into an ordered key/value view (`OrderedDictionary`) honoring delimiter,
    ///    charset, sentinel, parameter limits, and `allowDots`/`decodeDotInKeys`.
    /// 3. Merge parsed key paths into a single `[String: Any]` while preserving insertion order
    ///    semantics, respecting list format and duplicate handling.
    /// 4. Compact only when an `Undefined` is present (to avoid unnecessary work).
    /// 5. Perform an *iterative* deep bridge of `[String: Any?]` → `[String: Any]` to avoid recursion.
    /// 6. If the temporary optional graph is *very* deep (heuristically), schedule its destruction
    ///    on the main thread (`Utils.dropOnMainThread`) to sidestep destructor recursion in libswift.
    ///
    /// - Parameters:
    ///   - input: See `decode`.
    ///   - options: See `decode`.
    ///
    /// - Returns: A fully bridged `[String: Any]` ready for use by callers.
    ///
    /// - Throws: Same errors as `decode`.
    ///
    /// - Safety valve:
    ///   The “main-thread drop” is only about where ARC performs the *final release* of the temporary
    ///   intermediate graph (`[String: Any?]`). The returned value is fully bridged and independent.
    @usableFromInline
    internal static func _decodeSyncCore(
        _ input: Any?,
        options: DecodeOptions = .init()
    ) throws -> [String: Any] {
        // Type check (match Kotlin behavior)
        guard
            input == nil
                || input is String
                || input is [String: Any]
                || input is [String: Any?]
                || input is [AnyHashable: Any]
        else {
            throw NSError(
                domain: "Qs.decode",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "The input must be a String or a Map<String, Any?>"
                ]
            )
        }

        // Early outs for empty
        if input == nil { return [:] }
        if let string = input as? String, string.isEmpty { return [:] }
        if let mapAnyHashable = input as? [AnyHashable: Any], mapAnyHashable.isEmpty { return [:] }
        if let mapStringAny = input as? [String: Any], mapStringAny.isEmpty { return [:] }
        if let mapStringOptionalAny = input as? [String: Any?], mapStringOptionalAny.isEmpty { return [:] }

        // Build an ordered key/value view of the input
        let tmp: OrderedDictionary<String, Any> = try {
            switch input {
            case let string as String:
                return try QsSwift.Decoder.parseQueryStringValues(string, options: options)

            case let mapStringOptionalAny as [String: Any?]:
                return OrderedDictionary(
                    uniqueKeysWithValues: mapStringOptionalAny.map { ($0.key, $0.value ?? NSNull()) }
                )

            case let mapStringAny as [String: Any]:
                return OrderedDictionary(
                    uniqueKeysWithValues: mapStringAny.map { ($0.key, $0.value) }
                )

            case let mapAnyHashable as [AnyHashable: Any]:
                // Deterministic collision policy:
                // If distinct AnyHashable keys stringify to the same String,
                // prefer values coming from String keys over non-String keys.
                var od: OrderedDictionary<String, Any> = [:]
                var rank: [String: Int] = [:]  // higher rank wins: String=2, non-String=1

                for (key, value) in mapAnyHashable {
                    let stringKey = String(describing: key)
                    let keyTypeRank = (key is String) ? 2 : 1
                    if let old = rank[stringKey] {
                        if keyTypeRank >= old {  // String beats non-String; ties keep later value
                            od[stringKey] = value
                            rank[stringKey] = keyTypeRank
                        }
                    } else {
                        od[stringKey] = value
                        rank[stringKey] = keyTypeRank
                    }
                }
                return od

            default:
                return [:]
            }
        }()

        // If there are too many top-level params, match Kotlin: disable list parsing
        var finalOptions = options
        if options.parseLists, options.listLimit > 0, tmp.count > options.listLimit {
            finalOptions = options.copy(parseLists: false)
        }

        // Merge each parsed key structure into the final object, preserving order
        var obj: [String: Any] = [:]
        if !tmp.isEmpty {
            for (key, value) in tmp {
                let parsed = try QsSwift.Decoder.parseKeys(
                    givenKey: key,
                    value: value,
                    options: finalOptions,
                    valuesParsed: (input is String)
                )

                // (a) If the first parsed thing is a map, adopt it wholesale (fast path)
                if obj.isEmpty, let firstMap = parsed as? [String: Any] {
                    obj = firstMap
                    continue
                }

                // (b) If the first parsed thing is a *list* (e.g. top-level "[]"),
                //     objectify it as "0","1",... so tests like "[]=&a=b" pass.
                if obj.isEmpty, let firstList = parsed as? [Any] {
                    var indexedMap: [String: Any] = [:]
                    for (index, element) in firstList.enumerated() where !(element is Undefined) {
                        indexedMap[String(index)] = element
                    }
                    obj = indexedMap
                    continue
                }

                // (c) Otherwise, merge into the existing object
                //
                // NOTE: Only objectify top-level *list* fragments to {"0":..., "1":...}.
                // If `parsed` is nil, do not merge (avoids creating a "nil" key on inputs like "&").
                if let list = parsed as? [Any] {
                    // Top-level array fragment → convert to string-indexed map,
                    // dropping Undefined placeholders so we only add real values.
                    var indexed: [String: Any] = [:]
                    for (index, element) in list.enumerated() where !(element is Undefined) {
                        indexed[String(index)] = element
                    }
                    if let merged = Utils.merge(target: obj, source: indexed, options: finalOptions)
                        as? [String: Any]
                    {
                        obj = merged
                    }
                } else if let parsed = parsed {
                    // Non-array, non-nil fragment → merge as-is
                    if let merged = Utils.merge(target: obj, source: parsed, options: finalOptions)
                        as? [String: Any]
                    {
                        obj = merged
                    }
                }  // else: parsed == nil → nothing to merge
            }
        }

        // Work on optionals for Utils.compact
        var tmpOpt: [String: Any?] = obj.mapValues { $0 }

        // Only compact if we actually saw Undefined anywhere
        let compactedOpt: [String: Any?] = {
            if Utils.containsUndefined(tmpOpt) {
                return Utils.compact(&tmpOpt, allowSparseLists: finalOptions.allowSparseLists)
            } else {
                return tmpOpt
            }
        }()

        // Iterative deep-bridge to avoid recursion in Swift runtime
        let bridgedAny = Utils.deepBridgeToAnyIterative(compactedOpt)
        guard let bridged = bridgedAny as? [String: Any] else {
            assertionFailure("Bridge did not return [String: Any], got \(type(of: bridgedAny))")
            return [:]
        }

        // Heuristic: schedule temp graph drop on main to avoid deep destructor recursion
        if options.depth >= MAIN_DROP_THRESHOLD
            || Utils.needsMainDrop(compactedOpt, threshold: MAIN_DROP_THRESHOLD)
        {
            Utils.dropOnMainThread(compactedOpt)
        }

        return bridged
    }
}

import Foundation
import OrderedCollections

extension QsSwift.Decoder {
    /// Parses a raw query string into an ordered map of `key → value`, where `value` may be:
    /// - a `String`
    /// - an array of strings (when `comma == true`, preserving empty segments)
    /// - `NSNull` when `strictNullHandling == true` and no `=` was present
    ///
    /// Features handled here:
    /// - Custom delimiter (`Delimiter`) — string or regex‑based splitter
    /// - `ignoreQueryPrefix` — drops a leading `?`
    /// - Charset sentinel (`utf8=✓` or numeric‑entity) to auto‑select `.utf8` vs `.isoLatin1`
    /// - `parameterLimit` + `throwOnLimitExceeded`
    /// - Duplicate keys according to `duplicates` policy
    /// - `strictNullHandling` (parameters without `=` become `NSNull`)
    /// - Optional interpretation of numeric entities in latin‑1 mode
    /// - Special case of `"[]="`: if the RHS has already become an **array** (via `comma`), wrap it
    ///   to form a list‑of‑lists; otherwise leave scalars alone and let `parseObject` handle the `[]` segment
    ///
    /// This function **does not** build nested structures from bracketed keys; it only returns the
    /// ordered flat view that `parseKeys`/`parseObject` will assemble later. Default decoding falls back
    /// to the original literal when percent‑decoding fails.
    ///
    /// - Parameters:
    ///   - str: The raw query string (without or with a leading `?`).
    ///   - options: Decoding options.
    /// - Returns: An `OrderedDictionary` preserving parameter insertion order (post‑split).
    /// - Throws: `.parameterLimitNotPositive`, `.parameterLimitExceeded`, `.listLimitExceeded`.
    @usableFromInline
    internal static func parseQueryStringValues(
        _ str: String,
        options: DecodeOptions = .init()
    ) throws -> OrderedDictionary<String, Any> {
        var obj: OrderedDictionary<String, Any> = [:]

        // Strip "?" if requested (do not globally normalize %5B/%5D; normalize only within the key slice).
        let cleanStr =
            (options.ignoreQueryPrefix && str.hasPrefix("?"))
            ? String(str.dropFirst())
            : str

        // Parameter limit handling (Int.max == effectively unlimited)
        let limit: Int? = (options.parameterLimit == .max) ? nil : options.parameterLimit
        if let limit, limit <= 0 {
            throw DecodeError.parameterLimitNotPositive
        }

        // Split into parts using the provided delimiter
        let allParts: [String] = options.delimiter.split(input: cleanStr)
        let parts: [String] = {
            guard let limit else { return allParts }
            // If throwing, allow peeking one past the limit to error out cleanly.
            let takeCount = options.throwOnLimitExceeded ? (limit + 1) : limit
            return Array(allParts.prefix(takeCount))
        }()

        if let limit, options.throwOnLimitExceeded, parts.count > limit {
            throw DecodeError.parameterLimitExceeded(limit: limit)
        }

        // Charset sentinel support
        var skipIndex = -1
        var charset = options.charset

        if options.charsetSentinel {
            for index in parts.indices {
                let token = parts[index]
                // Allow UTF8 case and hex-digit case variations
                if token.lowercased().hasPrefix("utf8="),
                    let kind = Sentinel.match(encodedPart: token, caseInsensitive: true)
                {
                    charset = (kind == .charset) ? .utf8 : .isoLatin1
                    skipIndex = index
                    break
                }
            }
        }

        // Walk all parts
        for index in parts.indices {
            if index == skipIndex { continue }

            let part = parts[index]

            // IMPORTANT: We prefer the '=' that immediately follows a closing bracket (']=')
            // when present anywhere in the token. Some inputs legitimately contain multiple
            // '=' characters (e.g. values like "c=d"). Choosing the very first '=' can
            // mis-split keys like "a[b]=c=d". Keeping this heuristic preserves historical
            // qs behavior across ports.
            //
            // Also note: we *only* normalize %5B/%5D within the **key slice** after we find
            // `pos`, so scanning for "]=" here does not interact with percent-decoding.
            let bracketEqualsPos: Int = {
                if let range = part.range(of: "]=") {
                    return part.distance(from: part.startIndex, to: range.lowerBound) + 1
                }
                return -1
            }()
            let pos: Int = {
                if bracketEqualsPos == -1 {
                    if let eqIndex = part.firstIndex(of: "=") {
                        return part.distance(from: part.startIndex, to: eqIndex)
                    }
                    return -1
                }
                return bracketEqualsPos
            }()

            // Detect literal "[]" in the key only; support encoded forms.
            let hadBracketedEmpty: Bool = {
                if pos == -1 { return false }
                let keyOnly = String(part.prefix(pos))
                let normalized =
                    keyOnly
                    .replacingOccurrences(of: "%5B", with: "[", options: .caseInsensitive)
                    .replacingOccurrences(of: "%5D", with: "]", options: .caseInsensitive)
                return normalized.hasSuffix("[]")
            }()

            let key: String
            var value: Any?

            if pos == -1 {
                key = options.decodeKey(part, charset: charset) ?? part
                value = options.strictNullHandling ? NSNull() : ""
            } else {
                let keyRaw = String(part.prefix(pos))
                let rhs = String(part.dropFirst(pos + 1))

                key = options.decodeKey(keyRaw, charset: charset) ?? keyRaw
                let isFirstOccurrence = (obj[key] == nil)

                // Determine current list length for limit checks (only if key already has a list)
                let currentLen = effectiveListLength(obj[key])

                let parsed = try parseListValue(
                    rhs,
                    options: options,
                    currentListLength: currentLen,
                    isFirstOccurrence: isFirstOccurrence
                )

                // IMPORTANT: distinguish custom decoder vs default decoder
                if let arr = parsed as? [String] {
                    if let custom = options._decoder {
                        let mapped = arr.map { custom($0, charset, .value) }
                        value = mapped.map { $0 ?? NSNull() } as [Any]
                    } else {
                        // default decoder: fall back to original literal when decoding fails
                        value = arr.map { Utils.decode($0, charset: charset) ?? $0 } as [Any]
                    }
                } else if let scalar = parsed as? String {
                    if let custom = options._decoder {
                        value = custom(scalar, charset, .value)  // may be nil; keep it nil
                    } else {
                        value = Utils.decode(scalar, charset: charset) ?? scalar
                    }
                } else if let overflow = parsed as? [AnyHashable: Any], Utils.isOverflow(overflow) {
                    value = decodeOverflowElements(overflow, options: options, charset: charset)
                } else {
                    value = parsed
                }
            }

            // Interpret numeric entities if asked (ISO‑8859‑1 only).
            //
            // Behavioral note / Kotlin & reference‑port parity:
            // When `comma == true` has produced an *array* at this point, we intentionally
            // collapse that array into a single **comma‑joined String** and interpret HTML
            // numeric entities on that scalar. If the key was written as `a[]=...`, the
            // scalar result is then wrapped by the `[]` handling to yield a **single‑element
            // list** (e.g., ["1,☺"]). This matches the semantics in the Kotlin port and
            // keeps the decode pipeline deterministic even when values contained commas.
            //
            // If you need to preserve array shape while also interpreting numeric entities,
            // do not enable `interpretNumericEntities`, or pre‑decode/transform your data
            // before passing it to Qs.
            if let val = value, !Utils.isEmpty(val), options.interpretNumericEntities,
                charset == .isoLatin1
            {
                if let overflow = val as? [AnyHashable: Any], Utils.isOverflow(overflow) {
                    value = interpretNumericEntitiesInOverflow(overflow)
                } else {
                    let text: String
                    if let arr = val as? [Any] {
                        text = arr.map { String(describing: $0) }.joined(separator: ",")
                    } else if let arrOpt = val as? [Any?] {
                        text = arrOpt.map { String(describing: $0 ?? NSNull()) }.joined(separator: ",")
                    } else {
                        text = String(describing: val)
                    }
                    value = Utils.interpretNumericEntities(text)
                }
            }

            // Force list-of-lists only when RHS is already an array (comma path).
            if hadBracketedEmpty {
                if let arr = value as? [Any] {
                    value = [arr]
                } else if let arrOpt = value as? [Any?] {
                    value = [arrOpt.map { $0 ?? NSNull() }]
                } else if let overflow = value as? [AnyHashable: Any], Utils.isOverflow(overflow) {
                    // Explicit "[]": preserve list-of-lists semantics even when comma overflow
                    // temporarily used indexed-map fallback.
                    if let dense = overflowElementsAsArray(overflow, listLimit: options.listLimit) {
                        value = [dense]
                    } else {
                        // Avoid unbounded dense allocation; keep overflow-map representation.
                        value = overflow
                    }
                }
                // else leave scalars as-is; parseObject will handle "[]"
            }

            // Duplicates handling (only arrayify on subsequent duplicates, like Kotlin)
            let exists = (obj[key] != nil)
            switch options.duplicates {
            case .combine:
                if exists {
                    let prev: Any? = obj[key] ?? nil
                    let combined = Utils.combine(prev, value, listLimit: options.listLimit)
                    if let combinedArray = combined as? [Any?] {
                        obj[key] = combinedArray.map { $0 ?? NSNull() }  // normalize optionals
                    } else if let combinedArray = combined as? [Any] {
                        obj[key] = combinedArray
                    } else {
                        obj[key] = combined
                    }
                } else {
                    obj[key] = value ?? NSNull()
                }
            case .last:
                obj[key] = value ?? NSNull()
            case .first:
                if !exists { obj[key] = value ?? NSNull() }
            }
        }

        return obj
    }

    /// Decodes string payloads stored in overflow dictionaries so fallback path
    /// remains consistent with the normal comma list decoding behavior.
    private static func decodeOverflowElements(
        _ overflow: [AnyHashable: Any],
        options: DecodeOptions,
        charset: String.Encoding
    ) -> [AnyHashable: Any] {
        var out = overflow

        if let custom = options._decoder {
            for (key, rawValue) in overflow where !Utils.isOverflowKey(key) {
                guard let scalar = rawValue as? String else { continue }
                out[key] = custom(scalar, charset, .value) ?? NSNull()
            }
        } else {
            for (key, rawValue) in overflow where !Utils.isOverflowKey(key) {
                guard let scalar = rawValue as? String else { continue }
                out[key] = Utils.decode(scalar, charset: charset) ?? scalar
            }
        }

        return out
    }

    /// Computes logical list length across supported internal representations.
    private static func effectiveListLength(_ value: Any?) -> Int {
        if let arr = value as? [Any] { return arr.count }
        if let arrOpt = value as? [Any?] { return arrOpt.count }
        if let overflow = value as? [AnyHashable: Any], Utils.isOverflow(overflow) {
            let metadataMax = Utils.overflowMaxIndex(overflow) ?? -1
            let explicitMax = overflow.keys.compactMap(Utils.intIndex).max() ?? -1
            return max(metadataMax, explicitMax) + 1
        }
        return 0
    }

    /// Applies numeric-entity interpretation to overflow-map string elements
    /// without collapsing the indexed shape.
    private static func interpretNumericEntitiesInOverflow(
        _ overflow: [AnyHashable: Any]
    ) -> [AnyHashable: Any] {
        var out = overflow
        for (key, rawValue) in overflow where !Utils.isOverflowKey(key) {
            guard let text = rawValue as? String else { continue }
            out[key] = Utils.interpretNumericEntities(text)
        }
        return out
    }

    /// Materializes an overflow dictionary into a dense, index-ordered array payload.
    /// Missing indices are represented as `NSNull` to preserve positional semantics.
    ///
    /// Returns `nil` when the dense size would be unbounded for the current parser limits.
    private static func overflowElementsAsArray(
        _ overflow: [AnyHashable: Any],
        listLimit: Int
    ) -> [Any]? {
        let explicitMax = overflow.keys.compactMap(Utils.intIndex).max() ?? -1
        let metadataMax = Utils.overflowMaxIndex(overflow) ?? -1
        let maxIndex = max(explicitMax, metadataMax)
        guard maxIndex >= 0 else { return [] }

        let (elementCount, overflowed) = maxIndex.addingReportingOverflow(1)
        guard !overflowed else { return nil }

        let normalizedListLimit = max(listLimit, 0)
        let nearLimitAllowance: Int = {
            let (value, didOverflow) = normalizedListLimit.addingReportingOverflow(1)
            return didOverflow ? Int.max : value
        }()
        let materializationLimit = max(nearLimitAllowance, overflowDenseArrayMaterializationFloor)
        guard elementCount <= materializationLimit else { return nil }

        var out = Array(repeating: NSNull() as Any, count: elementCount)
        for (key, value) in overflow where !Utils.isOverflowKey(key) {
            guard let idx = Utils.intIndex(key), idx >= 0, idx <= maxIndex else { continue }
            out[idx] = value
        }
        return out
    }

    /// Lower bound for dense overflow materialization when applying parser limits.
    /// This keeps modest sparse overflows materializable even when `listLimit` is very small,
    /// preserving list-like semantics instead of immediately falling back to overflow maps.
    /// At 4_096 elements, pointer-sized storage is roughly 32 KiB (4_096 * 8 bytes) before
    /// container overhead, which keeps the memory tradeoff bounded.
    private static let overflowDenseArrayMaterializationFloor = 4_096
}

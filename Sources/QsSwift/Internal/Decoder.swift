import Foundation
import OrderedCollections

/// A helper for decoding query strings into structured data.
///
/// Pipeline overview:
/// 1. `parseQueryStringValues` splits and decodes the raw string into an ordered
///    flat view of `key → value` pairs (values may be `String`, arrays when `comma`,
///    or `NSNull` for strict nulls).
/// 2. For each pair, `parseKeys` turns a bracket/dot path into segments (with
///    depth handling and **remainder wrapping**). If the key contains more bracket
///    groups than `depth` allows and `strictDepth == false`, the unprocessed
///    remainder is collapsed into **one synthetic trailing segment**; if an
///    unterminated bracket group is encountered, the raw remainder is wrapped
///    the same way. With `strictDepth == true`, only *well‑formed* overflow throws.
/// 3. The caller merges fragments into the final object.
internal enum Decoder {

    // MARK: - Private helpers

    /// Interprets a would‑be list element and enforces list limits (used by both
    /// `parseQueryStringValues` and `parseObject`).
    ///
    /// Behavior:
    /// - If `options.comma == true` and `value` is a non-empty `String` containing commas,
    ///   split it into a `[String]` (preserving empty segments). Example: `"a,,b"` → `["a", "", "b"]`.
    /// - If `throwOnLimitExceeded == true`, validates both the split count (for comma lists)
    ///   and the *next* append (`currentListLength`) against `listLimit`.
    /// - Otherwise returns `value` unchanged.
    ///
    /// - Parameters:
    ///   - value: The raw (decoded) RHS value for the current key part.
    ///   - options: The active `DecodeOptions`.
    ///   - currentListLength: The current length of the list under construction for this key, if any.
    /// - Returns: Either the original `value`, or a `[String]` when comma-splitting applies.
    /// - Throws: `.listLimitExceeded`.
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    private static func parseListValue(
        _ value: Any?,
        options: DecodeOptions,
        currentListLength: Int
    ) throws -> Any? {
        if let s = value as? String, !s.isEmpty, options.comma, s.contains(",") {
            let splitVal = s.split(separator: ",", omittingEmptySubsequences: false).map(
                String.init)
            if options.throwOnLimitExceeded, splitVal.count > options.listLimit {
                throw DecodeError.listLimitExceeded(limit: options.listLimit)
            }
            return splitVal
        }

        if options.throwOnLimitExceeded, currentListLength >= options.listLimit {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }

        return value
    }

    // MARK: - Public-ish internals

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
    internal static func parseQueryStringValues(
        _ str: String,
        options: DecodeOptions = .init()
    ) throws -> OrderedDictionary<String, Any> {
        var obj: OrderedDictionary<String, Any> = [:]

        // Strip "?" if requested, and normalize bracket encodings
        let cleanStr = (options.ignoreQueryPrefix ? String(str.drop(while: { $0 == "?" })) : str)
            .replacingOccurrences(of: "%5B", with: "[", options: [.caseInsensitive])
            .replacingOccurrences(of: "%5D", with: "]", options: [.caseInsensitive])

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
            for i in parts.indices {
                let p = parts[i]
                // Allow UTF8 case and hex-digit case variations
                if p.lowercased().hasPrefix("utf8="),
                    let s = Sentinel.match(encodedPart: p, caseInsensitive: true)
                {
                    charset = (s == .charset) ? .utf8 : .isoLatin1
                    skipIndex = i
                    break
                }
            }
        }

        // Walk all parts
        for i in parts.indices {
            if i == skipIndex { continue }

            let part = parts[i]

            // Special handling when "]=" is present (prioritize that '=')
            let bracketEqualsPos: Int = {
                if let range = part.range(of: "]=") {
                    return part.distance(from: part.startIndex, to: range.lowerBound) + 1
                }
                return -1
            }()
            let pos: Int = {
                if bracketEqualsPos == -1 {
                    if let r = part.firstIndex(of: "=") {
                        return part.distance(from: part.startIndex, to: r)
                    }
                    return -1
                }
                return bracketEqualsPos
            }()

            // Track if the raw part literally had "[]="
            let hadBracketedEmpty = part.contains("[]=")

            let key: String
            var value: Any?

            if pos == -1 {
                key = options.decodeKey(part, charset: charset) ?? part
                value = options.strictNullHandling ? NSNull() : ""
            } else {
                let keyRaw = String(part.prefix(pos))
                let rhs = String(part.dropFirst(pos + 1))

                key = options.decodeKey(keyRaw, charset: charset) ?? keyRaw

                // Determine current list length for limit checks (only if key already has a list)
                let currentLen: Int = (obj[key] as? [Any])?.count ?? 0

                let parsed = try parseListValue(
                    rhs, options: options, currentListLength: currentLen)

                // IMPORTANT: distinguish custom decoder vs default decoder
                if let arr = parsed as? [String] {
                    if let custom = options._decoder {
                        // preserve element-level nils from custom decoder
                        value = arr.map { custom($0, charset, .value) } as [Any?]
                    } else {
                        // default decoder: fall back to original literal when decoding fails
                        value = arr.map { Utils.decode($0, charset: charset) ?? $0 } as [Any]
                    }
                } else if let s = parsed as? String {
                    if let custom = options._decoder {
                        value = custom(s, charset, .value)  // may be nil; keep it nil
                    } else {
                        value = Utils.decode(s, charset: charset) ?? s
                    }
                } else {
                    value = parsed
                }
            }

            // Interpret numeric entities if asked, only in ISO-8859-1 mode
            if let v = value, !Utils.isEmpty(v), options.interpretNumericEntities,
                charset == .isoLatin1
            {
                let text: String
                if let arr = v as? [Any] {
                    text = arr.map { String(describing: $0) }.joined(separator: ",")
                } else if let arrOpt = v as? [Any?] {
                    text = arrOpt.map { String(describing: $0 ?? NSNull()) }.joined(separator: ",")
                } else {
                    text = String(describing: v)
                }
                value = Utils.interpretNumericEntities(text)
            }

            // Force list-of-lists only when RHS is already an array (comma path).
            if hadBracketedEmpty {
                if let arr = value as? [Any] {
                    value = [arr]
                } else if let arrOpt = value as? [Any?] {
                    value = [arrOpt.map { $0 ?? NSNull() }]
                }
                // else leave scalars as-is; parseObject will handle "[]"
            }

            // Duplicates handling (only arrayify on subsequent duplicates, like Kotlin)
            let exists = (obj[key] != nil)
            switch options.duplicates {
            case .combine:
                if exists {
                    let prev: Any? = obj[key] ?? nil
                    let combined: [Any?] = Utils.combine(prev, value)
                    obj[key] = combined.map { $0 ?? NSNull() }  // normalize optionals
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

    /// Splits a single key into segments (respecting dot-notation and depth rules),
    /// then builds the nested structure for that key and assigns `value` at the leaf.
    ///
    /// Example:
    ///   givenKey: "a[b][0][]"            → segments: ["a", "[b]", "[0]", "[]"]
    ///   givenKey: "a.b.c" (allowDots)    → segments: ["a", "[b]", "[c]"]
    ///   → `parseObject(...)` turns segments into the nested fragment and assigns the leaf.
    ///
    /// - Parameters:
    ///   - givenKey: The raw key (may include brackets and/or dots).
    ///   - value: The decoded RHS value to insert.
    ///   - options: Active `DecodeOptions`.
    ///   - valuesParsed: `true` if `value` already reflects comma splitting, decoder, etc.
    /// - Returns: A nested map/array fragment suitable for merging into the root object.
    /// - Throws: `.depthExceeded` (if `strictDepth == true` and `depth` is exceeded).
    internal static func parseKeys(
        givenKey: String?,
        value: Any?,
        options: DecodeOptions,
        valuesParsed: Bool
    ) throws -> Any? {
        guard let givenKey, !givenKey.isEmpty else { return nil }

        let segments = try splitKeyIntoSegments(
            originalKey: givenKey,
            allowDots: options.getAllowDots,
            maxDepth: options.depth,
            strictDepth: options.strictDepth
        )

        return try parseObject(
            chain: segments,
            value: value,
            options: options,
            valuesParsed: valuesParsed
        )
    }

    /// Converts a key into bracket segments, enforcing depth and dot‑notation rules.
    ///
    /// Steps:
    /// 1. If `allowDots == true`, rewrite top‑level `.segment` into `[segment]` (dots inside brackets are ignored).
    /// 2. If `maxDepth == 0`, never split (return the whole key as a single segment).
    /// 3. Otherwise, extract up to `maxDepth` **balanced** bracket groups (including the brackets).
    /// 4. If there is a remainder:
    ///     • when `strictDepth == true` **and** all processed groups were well‑formed, throw `.depthExceeded`.
    ///     • otherwise (depth overflow **or** unterminated bracket group), stash the raw remainder
    ///       starting at the next unprocessed `'['` as a **single synthetic segment** by wrapping it:
    ///       `"[" + remainder + "]"`.
    ///
    /// Examples:
    ///   "a[b][c]"                   → ["a", "[b]", "[c]"]
    ///   "a.b.c" (allowDots)        → ["a", "[b]", "[c]"]
    ///   "a.b.c" (allowDots, depth=1, strictDepth=false) → ["a", "[b]", "[[c]]"]
    ///   "a[b][c][d]" (depth=2, strictDepth=false)      → ["a", "[b]", "[c]", "[[d]]"]
    ///   "a[b[c" (unterminated)                            → ["a", "[[b[c]"]
    ///
    /// - Parameters:
    ///   - originalKey: The input key string.
    ///   - allowDots: Whether `.` should be treated as `[segment]` at top level.
    ///   - maxDepth: Maximum number of bracket segments to extract.
    ///   - strictDepth: Throw instead of collapsing remainder when over limit and well‑formed.
    /// - Returns: An array of segments to drive `parseObject`.
    /// - Throws: `.depthExceeded` when `strictDepth == true` and the overflow is well‑formed.
    internal static func splitKeyIntoSegments(
        originalKey: String,
        allowDots: Bool,
        maxDepth: Int,
        strictDepth: Bool
    ) throws -> [String] {
        // Depth 0 semantics: never split, never transform (qs/Kotlin parity).
        if maxDepth <= 0 {
            return [originalKey]
        }

        // Apply top-level dot→bracket only when allowDots is enabled.
        let key: String = allowDots ? dotToBracket(originalKey) : originalKey

        // Prepare result; reserve based on '[' count.
        var segments: [String] = []
        segments.reserveCapacity(key.filter { $0 == "[" }.count + 1)

        // Work with a character array for index arithmetic.
        let chars = Array(key)
        let n = chars.count

        // Find the first '[' to separate the non-bracket parent prefix.
        var firstOpen = -1
        var idx = 0
        while idx < n, chars[idx] != "[" { idx += 1 }
        firstOpen = (idx < n) ? idx : -1

        // Append the parent prefix (if any).
        if firstOpen > 0 {
            segments.append(String(chars[0..<firstOpen]))
        } else if firstOpen == -1 {
            // No brackets at all → the whole key is a single literal segment.
            return [key]
        }

        // Walk bracket groups, collecting up to maxDepth balanced segments.
        var open = firstOpen
        var collected = 0
        var unterminated = false

        while open >= 0, collected < maxDepth {
            var i2 = open + 1
            var level = 1
            var close = -1

            // Balance nested '[' and ']' *within the same group* so "[with[inner]]" stays one segment.
            while i2 < n {
                if chars[i2] == "[" {
                    level += 1
                } else if chars[i2] == "]" {
                    level -= 1
                    if level == 0 {
                        close = i2
                        break
                    }
                }
                i2 += 1
            }

            if close < 0 {
                // Unterminated bracket group: stop collecting; stash from `open` as opaque remainder.
                unterminated = true
                break
            }

            // Include the surrounding brackets for this balanced group.
            segments.append(String(chars[open...close]))
            collected += 1

            // Advance to the next '[' after this closed group.
            var nextOpen = close + 1
            while nextOpen < n, chars[nextOpen] != "[" { nextOpen += 1 }
            open = (nextOpen < n) ? nextOpen : -1
        }

        // Handle remainder (either depth overflow or unterminated group).
        if open >= 0 {
            if strictDepth && !unterminated {
                throw DecodeError.depthExceeded(maxDepth: maxDepth)
            }
            // Kotlin parity: wrap the raw remainder (from the next unprocessed '[') in one synthetic segment.
            segments.append("[" + String(chars[open..<n]) + "]")
        }

        return segments
    }

    /// Builds a nested structure from a chain of key segments, inserting `value` at the leaf.
    ///
    /// Handles:
    /// - "[]" segments:
    ///   - When `parseLists == true`:
    ///     * `allowEmptyLists` → `[]` for empty or `nil` (when `strictNullHandling`)
    ///     * otherwise wraps scalars into single‑element lists
    ///   - When `parseLists == false`: treat as a dictionary with string key "0"
    /// - Numeric bracket segments like "[0]":
    ///   - When `parseLists == true` and index ≤ `listLimit`, produces a list shell filled with
    ///     `Undefined` up to the index, then assigns the leaf at that index.
    ///   - Otherwise produces a dictionary with the string key.
    /// - Key dot mapping: when `options.getDecodeDotInKeys == true`, `"%2E"/"%2e"` inside key segments
    ///   map to literal "." (case‑insensitive).
    /// - Array normalization: arrays of optionals are normalized to arrays of `Any` by mapping `nil → NSNull`.
    ///
    /// - Parameters:
    ///   - chain: Segments returned by `splitKeyIntoSegments`.
    ///   - value: The RHS value for the leaf (already post-processed if `valuesParsed == true`).
    ///   - options: Active `DecodeOptions`.
    ///   - valuesParsed: If `true`, `value` has already gone through decoder/comma logic.
    /// - Returns: The nested fragment (array or dictionary) to be merged into the root.
    private static func parseObject(
        chain: [String],
        value: Any?,
        options: DecodeOptions,
        valuesParsed: Bool
    ) throws -> Any? {
        // Compute current list length if the last segment is "[]"
        let currentListLength: Int = {
            guard let last = chain.last, last == "[]" else { return 0 }
            // Try to interpret parent as an integer index (best-effort mirroring the Kotlin)
            let parentKey = chain.dropLast().joined()
            guard let idx = Int(parentKey) else { return 0 }
            if let outer = value as? [Any?], idx >= 0, idx < outer.count,
                let inner = outer[idx] as? [Any?]
            {
                return inner.count
            }
            return 0
        }()

        var leaf: Any? =
            valuesParsed
            ? value
            : try parseListValue(value, options: options, currentListLength: currentListLength)

        // Walk backwards from leaf to root
        for i in stride(from: chain.count - 1, through: 0, by: -1) {
            let root = chain[i]
            let obj: Any?

            if root == "[]" && options.parseLists {
                if options.allowEmptyLists
                    && ((leaf as? String) == "" || (options.strictNullHandling && leaf == nil))
                {
                    obj = [Any]()  // empty list
                } else if let arr = leaf as? [Any] {
                    obj = arr
                } else if let arrOpt = leaf as? [Any?] {
                    obj = arrOpt.map { $0 ?? NSNull() }  // normalize to non-optional
                } else {
                    obj = [leaf ?? NSNull()]  // wrap scalar
                }
            } else {
                var mutableObj: [AnyHashable: Any] = [:]

                // Strip surrounding brackets, e.g. "[0]" -> "0", "[]" -> ""
                let cleanRoot: String = {
                    if root.hasPrefix("["), root.hasSuffix("]"), root.count >= 2 {
                        let start = root.index(after: root.startIndex)
                        let end = root.index(before: root.endIndex)
                        return String(root[start..<end])
                    }
                    return root
                }()

                // Optionally decode "%2E" into "." for keys
                let decodedRoot: String =
                    options.getDecodeDotInKeys
                    ? cleanRoot.replacingOccurrences(
                        of: "%2E", with: ".", options: .caseInsensitive)
                    : cleanRoot

                if (!options.parseLists || options.listLimit < 0) && decodedRoot.isEmpty {
                    // Treat "[]" as dictionary key "0"
                    mutableObj["0"] = (leaf ?? NSNull())
                    obj = mutableObj
                } else if let idx = Int(decodedRoot),
                    idx >= 0,
                    root != decodedRoot,  // must have been "[0]"
                    String(idx) == decodedRoot,
                    options.parseLists,
                    idx <= options.listLimit
                {
                    // valid bracketed numeric index ⇒ array shell
                    var list = Array(repeating: Undefined.instance as Any, count: idx + 1)
                    list[idx] = (leaf ?? NSNull())
                    obj = list
                } else {
                    // default: dictionary with *string* key
                    mutableObj[decodedRoot] = (leaf ?? NSNull())
                    obj = mutableObj
                }
            }

            leaf = obj
        }

        return leaf
    }

    // MARK: - Dot → Bracket converter (when allowDots = true)

    /// Rewrites `.segment` into `[segment]` when dot‑notation is enabled.
    ///
    /// Depth‑aware: only splits dots at **top level** (depth == 0); dots inside brackets
    /// are preserved. Skips pathological `..` and `.[` cases:
    /// - leading "." is preserved (e.g. ".a" → ".a")
    /// - the first dot in "a..b" is preserved (→ "a.[b]")
    /// - ".[" is treated as if the dot wasn’t there (→ "a[b]")
    ///
    /// This is the active implementation used by `splitKeyIntoSegments` (the old regex‑based
    /// approach is retained above only for historical reference).
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    private static func dotToBracket(_ s: String) -> String {
        // Depth-aware scanner that only splits dots at top level.
        if !s.contains(".") { return s }

        var out = String()
        out.reserveCapacity(s.count)
        let chars = Array(s)
        let n = chars.count
        var i = 0
        var depth = 0

        while i < n {
            let ch = chars[i]
            switch ch {
            case "[":
                depth += 1
                out.append(ch)
                i += 1

            case "]":
                if depth > 0 { depth -= 1 }
                out.append(ch)
                i += 1

            case ".":
                if depth == 0 {
                    let hasNext = (i + 1) < n
                    let next = hasNext ? chars[i + 1] : "\0"

                    if next == "[" {
                        // Skip the dot so "a.[b]" behaves like "a[b]"
                        i += 1
                    } else if !hasNext || next == "." {
                        // Trailing dot, or first dot in "a..b": keep literal "."
                        out.append(".")
                        i += 1
                    } else {
                        // Normal split: ".segment" → "[segment]"
                        var j = i + 1
                        while j < n && chars[j] != "." && chars[j] != "[" { j += 1 }
                        out.append("[")
                        out.append(String(chars[(i + 1)..<j]))
                        out.append("]")
                        i = j
                    }
                } else {
                    out.append(".")
                    i += 1
                }

            case "%":
                // Preserve percent sequences verbatim; we never split on %2E here.
                out.append("%")
                i += 1

            default:
                out.append(ch)
                i += 1
            }
        }

        return out
    }
}

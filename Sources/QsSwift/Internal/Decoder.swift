import Foundation
import OrderedCollections

/// A helper for decoding query strings into structured data.
///
/// Pipeline overview:
/// 1. `parseQueryStringValues` splits and decodes the raw string into an ordered
///    flat view of `key → value` pairs (values may be `String`, arrays when `comma`,
///    or `NSNull` for strict nulls).
/// 2. For each pair, `parseKeys` turns a bracket/dot path into segments (with
///    depth handling) and calls `parseObject` to build the nested fragment.
/// 3. The caller merges fragments into the final object.
internal enum Decoder {

    // MARK: - Private helpers

    /// Interprets a would-be list element and enforces list limits.
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

    // MARK: - Cached regexes

    /// Cached regex that rewrites dot-notation `.segment` → `[segment]`
    /// when `allowDots == true`. It matches a dot followed by a token that
    /// contains neither `.` nor `[` (i.e., `\.([^.\[]+)`).
    private static let dotRegex = try! NSRegularExpression(
        pattern: #"\.([^.\[]+)"#, options: []
    )

    // MARK: - Public-ish internals

    /// Parses a raw query string into an ordered map of `key → value`, where `value` may be:
    /// - a `String`
    /// - an array of strings/optionals (when `comma == true`), or
    /// - `NSNull`/`nil` when `strictNullHandling == true` and no `=` was present.
    ///
    /// Features handled here:
    /// - Custom delimiter (`Delimiter` protocol): simple string or regex-based splitter
    /// - `ignoreQueryPrefix`: drops a leading `?`
    /// - Charset sentinel (`utf8=✓` vs `utf8=&#10003;`) to auto-select `.utf8` vs `.isoLatin1`
    /// - `parameterLimit` + `throwOnLimitExceeded`
    /// - Duplicate keys according to `duplicates` policy
    /// - `strictNullHandling` (parameters without `=` become `nil`/`NSNull`)
    /// - Optional interpretation of numeric entities in latin-1 mode
    /// - Special‐case `"[]="` to wrap the RHS into a single-element list (when `parseLists == true`)
    ///
    /// This function **does not** build nested structures from bracketed keys; it only returns the
    /// ordered flat view that `parseKeys`/`parseObject` will assemble later.
    ///
    /// - Parameters:
    ///   - str: The raw query string (without or with a leading `?`).
    ///   - options: Decoding options.
    /// - Returns: An `OrderedDictionary` preserving parameter insertion order (post-split).
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
                   let s = Sentinel.match(encodedPart: p, caseInsensitive: true) {
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
                key = (options.getDecoder(part, charset: charset) as? String) ?? part
                value = options.strictNullHandling ? NSNull() : ""
            } else {
                let keyRaw = String(part.prefix(pos))
                let rhs = String(part.dropFirst(pos + 1))

                key = (options.getDecoder(keyRaw, charset: charset) as? String) ?? keyRaw

                // Determine current list length for limit checks (only if key already has a list)
                let currentLen: Int = (obj[key] as? [Any])?.count ?? 0

                let parsed = try parseListValue(
                    rhs, options: options, currentListLength: currentLen)

                // IMPORTANT: distinguish custom decoder vs default decoder
                if let arr = parsed as? [String] {
                    if let custom = options._decoder {
                        // preserve element-level nils from custom decoder
                        value = arr.map { custom($0, charset) } as [Any?]
                    } else {
                        // default decoder: fall back to original literal when decoding fails
                        value = arr.map { Utils.decode($0, charset: charset) ?? $0 } as [Any]
                    }
                } else if let s = parsed as? String {
                    if let custom = options._decoder {
                        value = custom(s, charset)  // may be nil; keep it nil
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

            // Only do the "[]=" single-element wrapping when list parsing is enabled.
            // When parseLists is false, "[]" becomes a string key "0" in parseObject.
            if hadBracketedEmpty, options.parseLists {
                if let arr = value as? [Any] {
                    value = [arr]
                } else if let arrOpt = value as? [Any?] {
                    value = [arrOpt.map { $0 ?? NSNull() }]
                } else {
                    value = [value ?? NSNull()]
                }
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
    ///   givenKey: "a[b][0][]"
    ///   → segments: ["a", "[b]", "[0]", "[]"]
    ///   → `parseObject(...)` turns it into `["a": ["b": [["<value>"]]]]`
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

    /// Converts a key into bracket segments, enforcing depth and dot-notation rules.
    ///
    /// Steps:
    /// 1. If `allowDots == true`, rewrite `.segment` to `[segment]` (but not `..` or `.[`).
    /// 2. If brackets are unbalanced, treat the entire key as a literal (no splitting).
    /// 3. If `maxDepth == 0`, never split (return the whole key as a single segment).
    /// 4. Otherwise, extract up to `maxDepth` bracketed segments (including the brackets).
    /// 5. If there is a remainder and `strictDepth == true`, throw `.depthExceeded`;
    ///    otherwise stash the remainder as a single trailing bracketed segment, e.g. `"[c][d]"`.
    ///
    /// Examples:
    ///   "a[b][c]"       → ["a", "[b]", "[c]"]
    ///   "a.b.c" (+dots) → ["a", "[b]", "[c]"]
    ///   "a[b][c][d]" with `maxDepth=2, strictDepth=false` → ["a", "[b]", "[c][d]"]
    ///
    /// - Parameters:
    ///   - originalKey: The input key string.
    ///   - allowDots: Whether `.` should be treated as `[segment]`.
    ///   - maxDepth: Maximum number of bracket segments to extract.
    ///   - strictDepth: Throw instead of collapsing remainder when over limit.
    /// - Returns: An array of segments to drive `parseObject`.
    /// - Throws: `.depthExceeded`.
    internal static func splitKeyIntoSegments(
        originalKey: String,
        allowDots: Bool,
        maxDepth: Int,
        strictDepth: Bool
    ) throws -> [String] {
        // 1) dot → bracket (only if allowDots)
        let key: String = allowDots ? dotToBracket(originalKey) : originalKey
        let opens = key.reduce(0) { $0 + ($1 == "[" ? 1 : 0) }
        let closes = key.reduce(0) { $0 + ($1 == "]" ? 1 : 0) }
        if opens != closes {
            // Treat the whole thing as a literal key (e.g. "[", "[[", "[hello[")
            return [key]
        }

        // Depth == 0: never split, never throw.
        if maxDepth <= 0 {
            return [key]
        }

        // 2) Scan for parent and bracket segments
        var segments: [String] = []
        segments.reserveCapacity(key.filter { $0 == "[" }.count + 1)

        let chars = Array(key)
        let n = chars.count
        var i = 0

        // parent before first '['
        while i < n, chars[i] != "[" { i += 1 }
        if i > 0 { segments.append(String(chars[0..<i])) }

        var depth = 0
        while i < n, depth < maxDepth {
            guard chars[i] == "[" else { break }
            let start = i
            i += 1
            while i < n, chars[i] != "]" { i += 1 }
            if i >= n { break }  // unmatched '['; remainder handled below
            // include the brackets, eg "[0]" or "[]"
            segments.append(String(chars[start...i]))
            depth += 1
            i += 1
            // advance to next '['
            while i < n, chars[i] != "[" { i += 1 }
        }

        // 3) Remainder (if any)
        if i < n {
            if strictDepth {
                throw DecodeError.depthExceeded(maxDepth: maxDepth)
            }
            // Stash the rest as a single bracketed segment, like Kotlin does:
            // "[" + key.substring(open) + "]"
            segments.append("[" + String(chars[i..<n]) + "]")
        }

        return segments
    }

    /// Builds a nested structure from a chain of key segments, inserting `value` at the leaf.
    ///
    /// Handles:
    /// - `"[]"` segments:
    ///   - When `parseLists == true`:
    ///     * `allowEmptyLists` → `[]` for empty or `nil` (when `strictNullHandling`)
    ///     * otherwise wraps scalars into single-element lists
    ///   - When `parseLists == false`: treat as a dictionary with string key `"0"`
    /// - Numeric bracket segments like `"[0]"`:
    ///   - When `parseLists == true` and index ≤ `listLimit`, produces a list shell filled with
    ///     `Undefined` up to the index, then assigns the leaf at that index.
    ///   - Otherwise produces a dictionary with the string key.
    /// - `encodeDotInKeys` counterpart for decoding: `"%2E"` in keys becomes literal `"."`.
    /// - `NSNull` normalization: `nil` leafs become `NSNull` so the graph is homogeneous (`Any`).
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

                if !options.parseLists && decodedRoot.isEmpty {
                    // "[]": treat as dict with *string* key "0"
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

    /// Rewrites `.segment` into `[segment]` when dot-notation is enabled,
    /// skipping pathological `..` and `.[` cases. Used by older path that relied on
    /// manual scanning (kept here for clarity/reference).
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    private static func dotToBracket(_ s: String) -> String {
        if !s.contains(".") { return s }
        var out = ""
        out.reserveCapacity(s.count)

        let end = s.endIndex
        var i = s.startIndex

        while i < end {
            let ch = s[i]
            if ch == "." {
                let j = s.index(after: i)
                if j < end, s[j] != ".", s[j] != "[" {
                    var k = j
                    while k < end {
                        let c = s[k]
                        if c == "." || c == "[" { break }
                        k = s.index(after: k)
                    }
                    let seg = s[j..<k]
                    out.append("[")
                    out.append(contentsOf: seg)
                    out.append("]")
                    i = k
                    continue
                }
            }
            out.append(ch)
            i = s.index(after: i)
        }

        return out
    }
}

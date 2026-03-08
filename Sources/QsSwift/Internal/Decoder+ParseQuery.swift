// swiftlint:disable file_length
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

        let takeCount: Int? = {
            guard let limit else { return nil }
            guard options.throwOnLimitExceeded else { return limit }
            let (peek, overflowed) = limit.addingReportingOverflow(1)
            return overflowed ? nil : peek
        }()

        // Split into raw parts using the provided delimiter.
        let parts = try collectRawParts(
            cleanStr,
            delimiter: options.delimiter,
            maxParts: takeCount
        )

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
                if hasASCIIUtf8Prefix(token),
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
            let pos = splitPosition(in: part)
            let hadBracketedEmpty =
                pos == -1
                ? false
                : hasBracketedEmptySuffix(part, splitOffset: pos)

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

    /// Attempts a fast, allocation-light decode path for *flat* query strings.
    ///
    /// Returns `nil` when the query contains any structured key syntax, or when
    /// options require the generic parser path.
    @usableFromInline
    internal static func decodeFlatQueryStringFast(
        _ str: String,
        options: DecodeOptions = .init()
    ) throws -> [String: Any]? {
        guard options._decoder == nil, !options.hasLegacyDecoder else { return nil }
        guard !options.interpretNumericEntities else { return nil }
        guard let stringDelimiter = options.delimiter as? StringDelimiter else { return nil }
        guard !stringDelimiter.value.isEmpty else { throw DecodeError.emptyDelimiter }
        guard stringDelimiter.value.utf8.count == 1,
            let delimiterByte = stringDelimiter.value.utf8.first
        else {
            return nil
        }

        let cleanStr =
            (options.ignoreQueryPrefix && str.hasPrefix("?"))
            ? String(str.dropFirst())
            : str

        let limit: Int? = (options.parameterLimit == .max) ? nil : options.parameterLimit
        if let limit, limit <= 0 {
            throw DecodeError.parameterLimitNotPositive
        }

        var parsed: [String: Any]?
        let usedContiguousStorage: Void? = try cleanStr.utf8.withContiguousStorageIfAvailable { bytes in
            parsed = try decodeFlatQueryFastBytes(
                bytes,
                options: options,
                delimiter: delimiterByte,
                limit: limit
            )
        }
        if usedContiguousStorage != nil {
            return parsed
        }

        let copied = Array(cleanStr.utf8)
        return try copied.withUnsafeBufferPointer { bytes in
            try decodeFlatQueryFastBytes(
                bytes,
                options: options,
                delimiter: delimiterByte,
                limit: limit
            )
        }
    }

    /// Common byte-oriented flat decoder used by contiguous and copied UTF-8 storage.
    private static func decodeFlatQueryFastBytes(
        _ bytes: UnsafeBufferPointer<UInt8>,
        options: DecodeOptions,
        delimiter: UInt8,
        limit: Int?
    ) throws -> [String: Any]? {
        let maxTokens: Int? = {
            guard let limit else { return nil }
            guard options.throwOnLimitExceeded else { return limit }
            let (peek, overflowed) = limit.addingReportingOverflow(1)
            return overflowed ? nil : peek
        }()

        if let limit, options.throwOnLimitExceeded {
            let preview = collectRawTokenByteRanges(
                bytes,
                delimiter: delimiter,
                maxParts: maxTokens
            )
            if preview.count > limit {
                throw DecodeError.parameterLimitExceeded(limit: limit)
            }
        }

        if !options.charsetSentinel {
            return try decodeFlatQuerySinglePass(
                bytes,
                options: options,
                delimiter: delimiter,
                limit: limit,
                charset: options.charset,
                skipTokenIndex: -1
            )
        }

        // Fast sentinel branch for common shape: first token is `utf8=...`.
        var firstTokenEnd = 0
        while firstTokenEnd < bytes.count, bytes[firstTokenEnd] != delimiter {
            firstTokenEnd &+= 1
        }
        let firstRange = 0..<firstTokenEnd
        if let sentinel = sentinelKind(in: bytes, tokenRange: firstRange) {
            let charset: String.Encoding = (sentinel == .charset) ? .utf8 : .isoLatin1
            return try decodeFlatQuerySinglePass(
                bytes,
                options: options,
                delimiter: delimiter,
                limit: limit,
                charset: charset,
                skipTokenIndex: 0
            )
        }

        // Fallback to the tokenized path so charset-sentinel parity is preserved
        // even when `utf8=...` is not the first token.
        let tokenRanges = collectRawTokenByteRanges(
            bytes,
            delimiter: delimiter,
            maxParts: maxTokens
        )

        if let limit, options.throwOnLimitExceeded, tokenRanges.count > limit {
            throw DecodeError.parameterLimitExceeded(limit: limit)
        }

        var charset = options.charset
        var skipIndex = -1
        for index in tokenRanges.indices {
            let tokenRange = tokenRanges[index]
            if let kind = sentinelKind(in: bytes, tokenRange: tokenRange) {
                charset = (kind == .charset) ? .utf8 : .isoLatin1
                skipIndex = index
                break
            }
        }

        var obj: [String: Any] = [:]
        obj.reserveCapacity(tokenRanges.count)

        for index in tokenRanges.indices {
            if index == skipIndex { continue }
            if try !consumeFlatToken(
                bytes,
                tokenRange: tokenRanges[index],
                options: options,
                charset: charset,
                obj: &obj
            ) {
                return nil
            }
        }

        if obj[""] != nil {
            obj.removeValue(forKey: "")
        }

        return obj
    }

    // swiftlint:disable function_parameter_count
    /// Single-pass flat parser that enforces parameter limits while decoding.
    private static func decodeFlatQuerySinglePass(
        _ bytes: UnsafeBufferPointer<UInt8>,
        options: DecodeOptions,
        delimiter: UInt8,
        limit: Int?,
        charset: String.Encoding,
        skipTokenIndex: Int
    ) throws -> [String: Any]? {
        var obj: [String: Any] = [:]
        let reserveHint = min(limit ?? 16, min(bytes.count, 15) + 1)
        obj.reserveCapacity(reserveHint)

        var tokenIndex = 0
        var tokenStart = 0
        var idx = 0

        while true {
            while idx < bytes.count, bytes[idx] != delimiter {
                idx &+= 1
            }

            let tokenRange = tokenStart..<idx
            tokenIndex &+= 1

            if let limit {
                if options.throwOnLimitExceeded {
                    if tokenIndex > limit {
                        throw DecodeError.parameterLimitExceeded(limit: limit)
                    }
                } else if tokenIndex > limit {
                    break
                }
            }

            if tokenIndex - 1 != skipTokenIndex {
                if try !consumeFlatToken(
                    bytes,
                    tokenRange: tokenRange,
                    options: options,
                    charset: charset,
                    obj: &obj
                ) {
                    return nil
                }
            }

            if idx >= bytes.count { break }
            idx &+= 1
            tokenStart = idx
        }

        if obj[""] != nil {
            obj.removeValue(forKey: "")
        }

        return obj
    }
    // swiftlint:enable function_parameter_count

    /// Parses one flat token into `obj`.
    ///
    /// Returns `false` when structured key syntax or duplicates require fallback.
    @inline(__always)
    private static func consumeFlatToken(
        _ bytes: UnsafeBufferPointer<UInt8>,
        tokenRange: Range<Int>,
        options: DecodeOptions,
        charset: String.Encoding,
        obj: inout [String: Any]
    ) throws -> Bool {
        let splitOffset = splitPosition(in: bytes, range: tokenRange)
        let keyRange: Range<Int> = {
            guard splitOffset >= 0 else { return tokenRange }
            return tokenRange.lowerBound..<(tokenRange.lowerBound + splitOffset)
        }()

        if hasStructuredSyntax(in: bytes, keyRange: keyRange, allowDots: options.getAllowDots) {
            return false
        }

        var key = decodeBytesRange(bytes, range: keyRange, charset: charset)
        if options.getDecodeDotInKeys {
            key = decodeDotEscapesInFlatKey(key)
        }
        if obj[key] != nil {
            return false
        }

        let value: Any = try {
            if splitOffset == -1 {
                return options.strictNullHandling ? NSNull() : ""
            }

            if options.throwOnLimitExceeded, options.listLimit <= 0 {
                throw DecodeError.listLimitExceeded(limit: options.listLimit)
            }

            let rhsRange = (tokenRange.lowerBound + splitOffset + 1)..<tokenRange.upperBound
            if options.comma, rangeContainsByte(bytes, range: rhsRange, byte: 0x2C) {
                return try decodeCommaListValue(bytes, range: rhsRange, options: options, charset: charset)
            }
            return decodeBytesRange(bytes, range: rhsRange, charset: charset)
        }()

        _ = obj.updateValue(value, forKey: key)
        return true
    }

    @inline(__always)
    private static func decodeCommaListValue(
        _ bytes: UnsafeBufferPointer<UInt8>,
        range: Range<Int>,
        options: DecodeOptions,
        charset: String.Encoding
    ) throws -> Any {
        if options.throwOnLimitExceeded {
            let maxParts: Int? = {
                let (peek, overflowed) = options.listLimit.addingReportingOverflow(1)
                return overflowed ? nil : peek
            }()
            let preview = collectCommaElementRanges(bytes, range: range, maxParts: maxParts)
            if preview.count > options.listLimit {
                throw DecodeError.listLimitExceeded(limit: options.listLimit)
            }

            var out: [Any] = []
            out.reserveCapacity(preview.count)
            for segment in preview {
                out.append(decodeBytesRange(bytes, range: segment, charset: charset))
            }
            return out
        }

        if options.listLimit >= 0 {
            let maxParts: Int? = {
                let (peek, overflowed) = options.listLimit.addingReportingOverflow(1)
                return overflowed ? nil : peek
            }()
            let preview = collectCommaElementRanges(bytes, range: range, maxParts: maxParts)
            if preview.count > options.listLimit {
                let full = collectCommaElementRanges(bytes, range: range, maxParts: nil)
                var overflow: [AnyHashable: Any] = [:]
                overflow.reserveCapacity(full.count + 1)
                for (index, segment) in full.enumerated() {
                    overflow[index] = decodeBytesRange(bytes, range: segment, charset: charset)
                }
                return Utils.markOverflow(overflow, maxIndex: full.count - 1)
            }

            var out: [Any] = []
            out.reserveCapacity(preview.count)
            for segment in preview {
                out.append(decodeBytesRange(bytes, range: segment, charset: charset))
            }
            return out
        }

        let full = collectCommaElementRanges(bytes, range: range, maxParts: nil)
        var overflow: [AnyHashable: Any] = [:]
        overflow.reserveCapacity(full.count + 1)
        for (index, segment) in full.enumerated() {
            overflow[index] = decodeBytesRange(bytes, range: segment, charset: charset)
        }
        return Utils.markOverflow(overflow, maxIndex: full.count - 1)
    }

    @inline(__always)
    private static func collectCommaElementRanges(
        _ bytes: UnsafeBufferPointer<UInt8>,
        range: Range<Int>,
        maxParts: Int?
    ) -> [Range<Int>] {
        if let maxParts, maxParts <= 0 { return [] }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(4)

        var start = range.lowerBound
        var idx = range.lowerBound
        while idx < range.upperBound {
            if bytes[idx] == 0x2C {  // ,
                ranges.append(start..<idx)
                if let maxParts, ranges.count >= maxParts { return ranges }
                start = idx + 1
            }
            idx += 1
        }

        ranges.append(start..<range.upperBound)
        return ranges
    }

    @inline(__always)
    private static func decodeBytesRange(
        _ bytes: UnsafeBufferPointer<UInt8>,
        range: Range<Int>,
        charset: String.Encoding
    ) -> String {
        var needsDecode = false
        for idx in range {
            let byte = bytes[idx]
            if byte == 0x2B || byte == 0x25 {  // + or %
                needsDecode = true
                break
            }
        }

        // swiftlint:disable:next optional_data_string_conversion
        let raw = String(decoding: bytes[range], as: UTF8.self)
        if !needsDecode { return raw }
        return Utils.decode(raw, charset: charset) ?? raw
    }

    @inline(__always)
    private static func decodeDotEscapesInFlatKey(_ input: String) -> String {
        let bytes = input.utf8
        var i = bytes.startIndex
        while i < bytes.endIndex {
            if matchesPercent2E(bytes, at: i) {
                var out: [UInt8] = []
                out.reserveCapacity(bytes.count)

                var j = bytes.startIndex
                while j < bytes.endIndex {
                    if matchesPercent2E(bytes, at: j),
                        let j2 = bytes.index(j, offsetBy: 2, limitedBy: bytes.endIndex),
                        j2 < bytes.endIndex
                    {
                        out.append(0x2E)  // "."
                        j = bytes.index(after: j2)
                        continue
                    }

                    out.append(bytes[j])
                    j = bytes.index(after: j)
                }

                // swiftlint:disable:next optional_data_string_conversion
                return String(decoding: out, as: UTF8.self)
            }

            i = bytes.index(after: i)
        }

        return input
    }

    @inline(__always)
    private static func matchesPercent2E(_ bytes: String.UTF8View, at index: String.UTF8View.Index) -> Bool {
        guard bytes[index] == 0x25 else { return false }  // "%"
        guard
            let i1 = bytes.index(index, offsetBy: 1, limitedBy: bytes.endIndex),
            i1 < bytes.endIndex,
            bytes[i1] == 0x32,  // "2"
            let i2 = bytes.index(index, offsetBy: 2, limitedBy: bytes.endIndex),
            i2 < bytes.endIndex
        else {
            return false
        }

        let third = bytes[i2]
        return third == 0x45 || third == 0x65  // "E" | "e"
    }

    /// Returns `true` when key bytes contain literal or encoded structured syntax.
    @inline(__always)
    private static func hasStructuredSyntax(
        in bytes: UnsafeBufferPointer<UInt8>,
        keyRange: Range<Int>,
        allowDots: Bool
    ) -> Bool {
        var idx = keyRange.lowerBound
        while idx < keyRange.upperBound {
            let byte = bytes[idx]

            if byte == 0x5B || byte == 0x5D {  // [ or ]
                return true
            }
            if allowDots, byte == 0x2E {  // .
                return true
            }

            if byte == 0x25, idx + 2 < keyRange.upperBound {  // %
                let b1 = bytes[idx + 1]
                let b2 = bytes[idx + 2]
                let foldedB2 = (b2 >= 0x41 && b2 <= 0x5A) ? (b2 | 0x20) : b2

                // %5B / %5D
                if b1 == 0x35, foldedB2 == 0x62 || foldedB2 == 0x64 {
                    return true
                }

                // %2E when allowDots is enabled
                if allowDots, b1 == 0x32, foldedB2 == 0x65 {
                    return true
                }
            }

            idx += 1
        }
        return false
    }

    @inline(__always)
    private static func rangeContainsByte(
        _ bytes: UnsafeBufferPointer<UInt8>,
        range: Range<Int>,
        byte: UInt8
    ) -> Bool {
        for idx in range where bytes[idx] == byte { return true }
        return false
    }

    /// Collects raw token ranges split by a single-byte delimiter.
    @inline(__always)
    private static func collectRawTokenByteRanges(
        _ bytes: UnsafeBufferPointer<UInt8>,
        delimiter: UInt8,
        maxParts: Int?
    ) -> [Range<Int>] {
        if let maxParts, maxParts <= 0 { return [] }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(16)

        var start = 0
        var idx = 0
        while idx < bytes.count {
            if bytes[idx] == delimiter {
                ranges.append(start..<idx)
                if let maxParts, ranges.count >= maxParts { return ranges }
                start = idx + 1
            }
            idx += 1
        }

        ranges.append(start..<bytes.count)
        return ranges
    }

    /// Returns split position inside `range` (`]=` preferred over first `=`).
    @inline(__always)
    private static func splitPosition(in bytes: UnsafeBufferPointer<UInt8>, range: Range<Int>) -> Int {
        var offset = 0
        var firstEqualsOffset = -1
        var previousWasCloseBracket = false

        for idx in range {
            let ch = bytes[idx]
            if ch == 0x3D {  // =
                if previousWasCloseBracket { return offset }
                if firstEqualsOffset == -1 { firstEqualsOffset = offset }
            }
            previousWasCloseBracket = (ch == 0x5D)  // ]
            offset += 1
        }

        return firstEqualsOffset
    }

    /// Exact sentinel check for raw token ranges (case-insensitive on ASCII bytes).
    @inline(__always)
    private static func sentinelKind(
        in bytes: UnsafeBufferPointer<UInt8>,
        tokenRange: Range<Int>
    ) -> Sentinel? {
        guard hasASCIIUtf8Prefix(bytes, range: tokenRange) else { return nil }
        if asciiCaseInsensitiveEquals(bytes, tokenRange: tokenRange, expected: sentinelCharsetBytes) {
            return .charset
        }
        if asciiCaseInsensitiveEquals(bytes, tokenRange: tokenRange, expected: sentinelISOBytes) {
            return .iso
        }
        return nil
    }

    @inline(__always)
    private static func hasASCIIUtf8Prefix(_ token: String) -> Bool {
        let utf8 = token.utf8
        guard utf8.count >= 5 else { return false }

        var iterator = utf8.makeIterator()
        guard
            let b0 = iterator.next(),
            let b1 = iterator.next(),
            let b2 = iterator.next(),
            let b3 = iterator.next(),
            let b4 = iterator.next()
        else { return false }

        let f0 = (b0 >= 0x41 && b0 <= 0x5A) ? (b0 | 0x20) : b0
        let f1 = (b1 >= 0x41 && b1 <= 0x5A) ? (b1 | 0x20) : b1
        let f2 = (b2 >= 0x41 && b2 <= 0x5A) ? (b2 | 0x20) : b2

        return f0 == 0x75  // u
            && f1 == 0x74  // t
            && f2 == 0x66  // f
            && b3 == 0x38  // 8
            && b4 == 0x3D  // =
    }

    @inline(__always)
    private static func hasASCIIUtf8Prefix(
        _ bytes: UnsafeBufferPointer<UInt8>,
        range: Range<Int>
    ) -> Bool {
        guard range.count >= 5 else { return false }
        let base = range.lowerBound
        let b0 = bytes[base]
        let b1 = bytes[base + 1]
        let b2 = bytes[base + 2]
        let b3 = bytes[base + 3]
        let b4 = bytes[base + 4]

        let f0 = (b0 >= 0x41 && b0 <= 0x5A) ? (b0 | 0x20) : b0
        let f1 = (b1 >= 0x41 && b1 <= 0x5A) ? (b1 | 0x20) : b1
        let f2 = (b2 >= 0x41 && b2 <= 0x5A) ? (b2 | 0x20) : b2

        return f0 == 0x75  // u
            && f1 == 0x74  // t
            && f2 == 0x66  // f
            && b3 == 0x38  // 8
            && b4 == 0x3D  // =
    }

    @inline(__always)
    private static func asciiCaseInsensitiveEquals(
        _ bytes: UnsafeBufferPointer<UInt8>,
        tokenRange: Range<Int>,
        expected: [UInt8]
    ) -> Bool {
        guard tokenRange.count == expected.count else { return false }

        var idx = tokenRange.lowerBound
        var expectedIndex = 0
        while idx < tokenRange.upperBound {
            let left = bytes[idx]
            let right = expected[expectedIndex]

            let foldedLeft: UInt8 = (left >= 0x41 && left <= 0x5A) ? (left | 0x20) : left
            let foldedRight: UInt8 = (right >= 0x41 && right <= 0x5A) ? (right | 0x20) : right
            if foldedLeft != foldedRight { return false }

            idx += 1
            expectedIndex += 1
        }

        return true
    }

    /// Cached sentinel bytes for case-insensitive byte matching.
    private static let sentinelCharsetBytes = Array(Sentinel.charsetString.utf8)
    private static let sentinelISOBytes = Array(Sentinel.isoString.utf8)

    /// Splits query tokens using the configured delimiter and preserves raw parts.
    private static func collectRawParts(
        _ input: String,
        delimiter: Delimiter,
        maxParts: Int?
    ) throws -> [String] {
        if let maxParts, maxParts <= 0 { return [] }

        if let literal = delimiter as? StringDelimiter {
            return try collectRawStringParts(input, delimiter: literal.value, maxParts: maxParts)
        }

        return collectRawIterableParts(
            delimiter.split(input: input),
            maxParts: maxParts
        )
    }

    /// Fast path for string delimiters using ordinal scanning.
    private static func collectRawStringParts(
        _ input: String,
        delimiter: String,
        maxParts: Int?
    ) throws -> [String] {
        if delimiter.isEmpty {
            throw DecodeError.emptyDelimiter
        }
        if let maxParts, maxParts <= 0 { return [] }

        var parts: [String] = []
        parts.reserveCapacity(16)

        let singleCharDelimiter = delimiter.count == 1
        let delimiterChar: Character? = singleCharDelimiter ? delimiter.first : nil

        var start = input.startIndex
        while true {
            if let maxParts, parts.count >= maxParts { break }

            let nextRange: Range<String.Index>? = {
                if singleCharDelimiter {
                    guard let delimiterChar else {
                        return nil
                    }
                    guard let idx = input[start...].firstIndex(of: delimiterChar) else {
                        return nil
                    }
                    return idx..<input.index(after: idx)
                }
                return input.range(of: delimiter, range: start..<input.endIndex)
            }()

            let end = nextRange?.lowerBound ?? input.endIndex
            parts.append(String(input[start..<end]))

            guard let nextRange else { break }
            start = nextRange.upperBound
        }

        return parts
    }

    /// Fallback path for regex/custom delimiters.
    private static func collectRawIterableParts(
        _ parts: [String],
        maxParts: Int?
    ) -> [String] {
        if let maxParts, maxParts <= 0 { return [] }
        guard let maxParts else { return parts }
        return Array(parts.prefix(maxParts))
    }

    /// Returns the preferred split position (`]=` preferred over first `=`).
    @inline(__always)
    private static func splitPosition(in part: String) -> Int {
        if let range = part.range(of: "]=") {
            return part.distance(from: part.startIndex, to: range.lowerBound) + 1
        }
        if let eq = part.firstIndex(of: "=") {
            return part.distance(from: part.startIndex, to: eq)
        }
        return -1
    }

    /// Detects normalized key suffix `[]`, allowing literal and encoded brackets to mix.
    @inline(__always)
    private static func hasBracketedEmptySuffix(_ part: String, splitOffset: Int) -> Bool {
        guard splitOffset > 0 else { return false }

        let splitIndex = part.index(part.startIndex, offsetBy: splitOffset)
        let bytes = part[..<splitIndex].utf8

        guard
            let beforeClose = consumeTrailingBracket(
                bytes,
                end: bytes.endIndex,
                literal: 0x5D,
                encodedNibble: 0x64
            ),
            consumeTrailingBracket(
                bytes,
                end: beforeClose,
                literal: 0x5B,
                encodedNibble: 0x62
            ) != nil
        else {
            return false
        }

        return true
    }

    @inline(__always)
    private static func consumeTrailingBracket(
        _ bytes: Substring.UTF8View,
        end: Substring.UTF8View.Index,
        literal: UInt8,
        encodedNibble: UInt8
    ) -> Substring.UTF8View.Index? {
        guard end > bytes.startIndex else { return nil }

        let last = bytes.index(before: end)
        if bytes[last] == literal { return last }

        guard last > bytes.startIndex else { return nil }
        let middle = bytes.index(before: last)
        guard middle > bytes.startIndex else { return nil }
        let first = bytes.index(before: middle)

        let lastByte = bytes[last]
        let foldedLast = (lastByte >= 0x41 && lastByte <= 0x5A) ? (lastByte | 0x20) : lastByte

        guard
            bytes[first] == 0x25,  // %
            bytes[middle] == 0x35,  // 5
            foldedLast == encodedNibble
        else {
            return nil
        }

        return first
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

import Foundation

extension QsSwift.Decoder {
    /// Interprets a would‑be list element and enforces list limits (used by both
    /// `parseQueryStringValues` and `parseObject`).
    ///
    /// Behavior:
    /// - If `options.comma == true` and `value` is a non-empty `String` containing commas,
    ///   split it into a `[String]` (preserving empty segments). Example: `"a,,b"` → `["a", "", "b"]`.
    /// - If `throwOnLimitExceeded == true`, validates flat comma values before splitting and
    ///   validates the *next* scalar append (`currentListLength`) against `listLimit`.
    /// - Comma groups under `[]=` are nested values and count as one outer list element.
    ///
    /// - Parameters:
    ///   - value: The raw (decoded) RHS value for the current key part.
    ///   - options: The active `DecodeOptions`.
    ///   - currentListLength: The current length of the list under construction for this key, if any.
    ///   - isFlatListValue: Whether a comma value is flat rather than nested under `[]=`.
    /// - Returns: Either the original `value`, or a `[String]` when comma-splitting applies.
    /// - Throws: `.listLimitExceeded`.
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    @usableFromInline
    internal static func parseListValue(
        _ value: Any?,
        options: DecodeOptions,
        currentListLength: Int,
        isFlatListValue: Bool = true
    ) throws -> Any? {
        if let stringVal = value as? String, !stringVal.isEmpty, options.comma, stringVal.contains(",") {
            if isFlatListValue, options.throwOnLimitExceeded {
                var commaCount = 0
                for byte in stringVal.utf8 where byte == 0x2C {
                    commaCount += 1
                    if commaCount >= options.listLimit {
                        throw DecodeError.listLimitExceeded(limit: options.listLimit)
                    }
                }
            }
            return splitCommaValue(stringVal)
        }

        if options.throwOnLimitExceeded, currentListLength >= options.listLimit {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }

        return value
    }

    /// Splits a comma-separated scalar preserving empty segments.
    private static func splitCommaValue(_ value: String) -> [String] {
        var parts: [String] = []
        let reserveHint = min(value.utf8.count, 7) + 1
        parts.reserveCapacity(reserveHint)

        var start = value.startIndex
        while true {
            let comma = value[start...].firstIndex(of: ",")
            let end = comma ?? value.endIndex
            parts.append(String(value[start..<end]))

            guard let comma else { break }
            start = value.index(after: comma)
        }

        return parts
    }
}

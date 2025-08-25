import Foundation

extension QsSwift.Decoder {
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
    @usableFromInline
    internal static func parseListValue(
        _ value: Any?,
        options: DecodeOptions,
        currentListLength: Int
    ) throws -> Any? {
        if options.throwOnLimitExceeded, options.listLimit == 0 {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }
        if let stringVal = value as? String, !stringVal.isEmpty, options.comma, stringVal.contains(",") {
            let splitVal = stringVal.split(separator: ",", omittingEmptySubsequences: false).map(
                String.init)
            if options.throwOnLimitExceeded,
                (currentListLength + splitVal.count) > options.listLimit
            {
                throw DecodeError.listLimitExceeded(limit: options.listLimit)
            }
            return splitVal
        }

        if options.throwOnLimitExceeded, currentListLength >= options.listLimit {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }

        return value
    }
}

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
    /// - If `throwOnLimitExceeded == false`, comma values that overflow the limit on first
    ///   occurrence fall back to indexed-object (overflow) representation.
    ///
    /// - Parameters:
    ///   - value: The raw (decoded) RHS value for the current key part.
    ///   - options: The active `DecodeOptions`.
    ///   - currentListLength: The current length of the list under construction for this key, if any.
    ///   - isFirstOccurrence: Whether this key has not been seen previously in the current query pass.
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
        isFirstOccurrence: Bool
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

            // qs@6.14.2 parity:
            // If comma splitting alone overflows and we are not throwing, the first occurrence
            // falls back to an indexed object shape instead of a list.
            if !options.throwOnLimitExceeded,
                isFirstOccurrence,
                splitVal.count > options.listLimit
            {
                var overflow: [AnyHashable: Any] = [:]
                overflow.reserveCapacity(splitVal.count + 1)
                for (index, element) in splitVal.enumerated() {
                    overflow[index] = element
                }
                return Utils.markOverflow(overflow, maxIndex: splitVal.count - 1)
            }

            return splitVal
        }

        if options.throwOnLimitExceeded, currentListLength >= options.listLimit {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }

        return value
    }
}

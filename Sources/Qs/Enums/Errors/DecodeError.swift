/// Errors emitted while decoding a query string into structured data.
public enum DecodeError: Error, Equatable, CustomStringConvertible {
    /// The `parameterLimit` option was set to `<= 0`.
    case parameterLimitNotPositive
    /// The number of key/value pairs exceeded `parameterLimit` and `throwOnLimitExceeded` is `true`.
    case parameterLimitExceeded(limit: Int)
    /// The number of list elements exceeded `listLimit` and `throwOnLimitExceeded` is `true`.
    case listLimitExceeded(limit: Int)
    /// A key’s nesting depth exceeded `depth` and `strictDepth` is `true`.
    case depthExceeded(maxDepth: Int)

    /// Human-readable description useful in tests and logs.
    public var description: String {
        switch self {
        case .parameterLimitNotPositive:
            return "Parameter limit must be a positive integer."
        case .parameterLimitExceeded(let limit):
            return
                "Parameter limit exceeded. Only \(limit) parameter\(limit == 1 ? "" : "s") allowed."
        case .listLimitExceeded(let limit):
            return
                "List limit exceeded. Only \(limit) element\(limit == 1 ? "" : "s") allowed in a list."
        case .depthExceeded(let maxDepth):
            return "Input depth exceeded depth option of \(maxDepth) and strictDepth is true."
        }
    }
}

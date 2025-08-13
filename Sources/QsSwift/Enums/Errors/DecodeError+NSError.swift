import Foundation

// Public keys that ObjC can also read via the shim
extension DecodeError {
    public static let userInfoLimitKey = "limit"
    public static let userInfoMaxDepthKey = "maxDepth"
}

extension DecodeError: LocalizedError, CustomNSError {
    public static var errorDomain: String { "io.github.techouse.qsswift.decode" }

    public var errorDescription: String? { description }

    public var errorCode: Int {
        switch self {
        case .parameterLimitNotPositive: return 1
        case .parameterLimitExceeded: return 2
        case .listLimitExceeded: return 3
        case .depthExceeded: return 4
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .parameterLimitNotPositive:
            return [:]

        case .parameterLimitExceeded(let limit),
            .listLimitExceeded(let limit):
            return [Self.userInfoLimitKey: limit]

        case .depthExceeded(let maxDepth):
            return [Self.userInfoMaxDepthKey: maxDepth]
        }
    }
}

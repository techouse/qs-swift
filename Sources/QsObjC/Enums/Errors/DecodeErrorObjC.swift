import Foundation
import QsSwift

@objc(QsDecodeErrorInfo)
@objcMembers
public final class DecodeErrorInfoObjC: NSObject {
    public static let domain = QsSwift.DecodeError.errorDomain
    public static let limitKey = QsSwift.DecodeError.userInfoLimitKey
    public static let maxDepthKey = QsSwift.DecodeError.userInfoMaxDepthKey
}

@objc(QsDecodeErrorCode)
public enum DecodeErrorCodeObjC: Int {
    case parameterLimitNotPositive = 1
    case parameterLimitExceeded = 2
    case listLimitExceeded = 3
    case depthExceeded = 4
}

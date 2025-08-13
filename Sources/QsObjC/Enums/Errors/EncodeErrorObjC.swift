import Foundation
import QsSwift

@objc(QsEncodeErrorInfo)
@objcMembers
public final class EncodeErrorInfoObjC: NSObject {
    /// NSError domain for encoding errors
    public static let domain = QsSwift.EncodeError.errorDomain
}

@objc(QsEncodeErrorCode)
public enum EncodeErrorCodeObjC: Int {
    case cyclicObject = 1
}

/// Optional tiny helper for ergonomics
@objc(QsEncodeError)
@objcMembers
public final class EncodeErrorObjC: NSObject {
    /// Returns the strongly-typed code if this is an encode error
    public static func kind(from error: NSError) -> EncodeErrorCodeObjC? {
        guard error.domain == EncodeErrorInfoObjC.domain else { return nil }
        return EncodeErrorCodeObjC(rawValue: error.code)
    }
}

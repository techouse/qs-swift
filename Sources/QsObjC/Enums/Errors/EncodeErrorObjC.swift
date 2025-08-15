import Foundation
import QsSwift

/// Obj-C surface for Swift `EncodeError` metadata.
@objc(QsEncodeErrorInfo)
@objcMembers
public final class EncodeErrorInfoObjC: NSObject {
    /// `NSError.domain` used by the Swift encoder when it throws.
    ///
    /// Use this to test whether an `NSError` originated from Qs encoding:
    ///
    /// ```objc
    /// if ([error.domain isEqualToString:QsEncodeErrorInfo.domain]) { ... }
    /// ```
    public static let domain = QsSwift.EncodeError.errorDomain
}

/// Obj-C mirror of Swift `EncodeError` cases.
///
/// Raw values are **stable** and safe to pass through `NSNumber` in Obj-C.
@objc(QsEncodeErrorCode)
public enum EncodeErrorCodeObjC: Int {
    /// The input graph contains a reference cycle (e.g. NSDictionary ↔ NSDictionary).
    case cyclicObject = 1
}

// Nice string for logs / debugging parity with Swift.
extension EncodeErrorCodeObjC: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cyclicObject: return "cyclicObject"
        }
    }
}

/// Small helpers for interrogating `NSError` produced by the encoder.
@objc(QsEncodeError)
@objcMembers
public final class EncodeErrorObjC: NSObject {

    /// Returns the strongly-typed code **iff** this is a Qs encode error; otherwise `nil`.
    ///
    /// ```objc
    /// if (QsEncodeError.kind(from: error).intValue == QsEncodeErrorCodeCyclicObject) { ... }
    /// ```
    public static func kind(from error: NSError) -> EncodeErrorCodeObjC? {
        guard error.domain == EncodeErrorInfoObjC.domain else { return nil }
        return EncodeErrorCodeObjC(rawValue: error.code)
    }

    /// Convenience boolean for the most common case check.
    public static func isCyclicObject(_ error: NSError) -> Bool {
        kind(from: error) == .cyclicObject
    }
}

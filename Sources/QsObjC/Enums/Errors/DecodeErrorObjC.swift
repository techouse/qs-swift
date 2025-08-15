#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Obj-C surface for Swift `DecodeError` metadata.
    ///
    /// - `domain` is the `NSError.domain` used when the Swift decoder throws.
    /// - `limitKey` and `maxDepthKey` are the `userInfo` keys attached to certain failures.
    @objc(QsDecodeErrorInfo)
    @objcMembers
    public final class DecodeErrorInfoObjC: NSObject {

        /// `NSError.domain` used by the Swift decoder.
        ///
        /// Example:
        /// ```objc
        /// if ([error.domain isEqualToString:QsDecodeErrorInfo.domain]) { ... }
        /// ```
        public static let domain = QsSwift.DecodeError.errorDomain

        /// `userInfo` key containing the limit value that was exceeded (when applicable).
        public static let limitKey = QsSwift.DecodeError.userInfoLimitKey

        /// `userInfo` key containing the configured maximum depth (when applicable).
        public static let maxDepthKey = QsSwift.DecodeError.userInfoMaxDepthKey
    }

    /// Obj-C mirror of Swift `DecodeError` cases.
    ///
    /// Raw values are **stable** and safe to pass through `NSNumber` in Obj-C.
    @objc(QsDecodeErrorCode)
    public enum DecodeErrorCodeObjC: Int {
        /// `parameterLimit` must be > 0.
        case parameterLimitNotPositive = 1
        /// The number of parameters exceeded `parameterLimit`.
        case parameterLimitExceeded = 2
        /// A list (array) exceeded `listLimit`.
        case listLimitExceeded = 3
        /// Nested depth exceeded `depth` (or `strictDepth` failed).
        case depthExceeded = 4
    }

    // Nice string for logs / debugging parity with Swift.
    extension DecodeErrorCodeObjC: CustomStringConvertible {
        public var description: String {
            switch self {
            case .parameterLimitNotPositive: return "parameterLimitNotPositive"
            case .parameterLimitExceeded: return "parameterLimitExceeded"
            case .listLimitExceeded: return "listLimitExceeded"
            case .depthExceeded: return "depthExceeded"
            }
        }
    }

    /// Small helpers for interrogating `NSError` produced by the decoder.
    @objc(QsDecodeError)
    @objcMembers
    public final class DecodeErrorObjC: NSObject {

        /// Returns the strongly-typed code **iff** this is a Qs decode error; otherwise `nil`.
        public static func kind(from error: NSError) -> DecodeErrorCodeObjC? {
            guard error.domain == DecodeErrorInfoObjC.domain else { return nil }
            return DecodeErrorCodeObjC(rawValue: error.code)
        }

        /// Convenience accessors for commonly attached `userInfo` values.
        ///
        /// - Returns the offending limit for `.parameterLimitExceeded` / `.listLimitExceeded`, if present.
        public static func limit(from error: NSError) -> Int? {
            error.userInfo[DecodeErrorInfoObjC.limitKey] as? Int
        }

        /// - Returns the configured max depth for `.depthExceeded`, if present.
        public static func maxDepth(from error: NSError) -> Int? {
            error.userInfo[DecodeErrorInfoObjC.maxDepthKey] as? Int
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

import Foundation
import QsSwift

@objc(QsSentinel)
public enum SentinelObjC: Int {
    case iso, charset

    var swift: QsSwift.Sentinel { self == .iso ? .iso : .charset }

    public var value: String {
        switch self {
        case .iso: return QsSwift.Sentinel.iso.value
        case .charset: return QsSwift.Sentinel.charset.value
        }
    }

    public var encoded: String {
        switch self {
        case .iso: return QsSwift.Sentinel.iso.encoded
        case .charset: return QsSwift.Sentinel.charset.encoded
        }
    }
}

// Swift-only description parity
extension SentinelObjC: CustomStringConvertible {
    public var description: String { encoded }
}

// MARK: - Obj-C bridge for helpers

/// Returns an NSNumber wrapping `QsSentinel` rawValue (.iso = 0, .charset = 1), or nil if no match.
@objc(QsSentinelBridge)
@objcMembers
public final class SentinelBridge: NSObject {
    /// Obj-C: returns boxed enum (or nil).
    public static func matchEncodedPart(_ part: NSString) -> NSNumber? {
        guard let s = QsSwift.Sentinel.match(encodedPart: part as String) else { return nil }
        let e: SentinelObjC = (s == .iso) ? .iso : .charset
        return NSNumber(value: e.rawValue)
    }

    /// Obj-C: returns boxed enum (or nil).
    public static func forCharset(_ rawEncoding: UInt) -> NSNumber? {
        guard let s = QsSwift.Sentinel.forCharset(String.Encoding(rawValue: rawEncoding)) else {
            return nil
        }
        let e: SentinelObjC = (s == .iso) ? .iso : .charset
        return NSNumber(value: e.rawValue)
    }
}

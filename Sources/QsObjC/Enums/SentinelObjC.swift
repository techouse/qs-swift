#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Obj-C visible mirror of Swift `QsSwift.Sentinel`.
    ///
    /// Notes:
    /// - Raw values are stable and match the Swift enum order (`.iso = 0`, `.charset = 1`)
    ///   so we can safely box/unbox through `NSNumber` for Objective-C.
    /// - This type exposes Swift helpers (`value`, `encoded`) so tests and callers
    ///   don’t need to reach into the Swift module directly.
    @objc(QsSentinel)
    public enum SentinelObjC: Int {
        case iso
        case charset

        /// Bridge to the underlying Swift type for internal use.
        /// Not `public` because it’s only used by our bridge layer.
        var swift: QsSwift.Sentinel { self == .iso ? .iso : .charset }

        /// Human-readable name (same as Swift: `"iso-8859-1"` or `"charset"`).
        public var value: String {
            switch self {
            case .iso: return QsSwift.Sentinel.iso.value
            case .charset: return QsSwift.Sentinel.charset.value
            }
        }

        /// Percent-encoded representation used in query strings
        /// (same as Swift: e.g. `"%E2%9C%93"` or similar depending on sentinel).
        public var encoded: String {
            switch self {
            case .iso: return QsSwift.Sentinel.iso.encoded
            case .charset: return QsSwift.Sentinel.charset.encoded
            }
        }
    }

    // Swift-only description parity
    extension SentinelObjC: CustomStringConvertible {
        /// Mirrors Swift’s `CustomStringConvertible` for nice logging/debugging.
        public var description: String { encoded }
    }

    // MARK: - Obj-C bridge for helpers

    /// Objective-C façade for Swift sentinel helpers that need to return boxed enums.
    ///
    /// Obj-C can’t return Swift enums directly in a nullable position without extra
    /// glue, so we return an `NSNumber` containing the enum’s `rawValue`:
    /// - `.iso` → `0`
    /// - `.charset` → `1`
    ///
    /// Callers can compare against those raw values or create `SentinelObjC(rawValue:)`.
    @objc(QsSentinelBridge)
    @objcMembers
    public final class SentinelBridge: NSObject {

        /// Returns an `NSNumber` wrapping `SentinelObjC.rawValue` if `part` matches
        /// a known sentinel’s *encoded* form; otherwise returns `nil`.
        ///
        /// Example:
        /// ```
        /// if let boxed = SentinelBridge.matchEncodedPart("%5B...%5D") {
        ///     let sentinel = SentinelObjC(rawValue: boxed.intValue)
        ///     ...
        /// }
        /// ```
        public static func matchEncodedPart(_ part: NSString) -> NSNumber? {
            guard let _sentinel = QsSwift.Sentinel.match(encodedPart: part as String) else { return nil }
            return _box(_sentinel)
        }

        /// Returns an `NSNumber` wrapping `SentinelObjC.rawValue` for a given
        /// Foundation string encoding (UTF-8, ISO-8859-1, etc.), or `nil` if the
        /// encoding doesn’t map to a known sentinel.
        ///
        /// - Parameter rawEncoding: A `NSStringEncoding`/`String.Encoding.rawValue`.
        public static func forCharset(_ rawEncoding: UInt) -> NSNumber? {
            guard let _sentinel = QsSwift.Sentinel.forCharset(String.Encoding(rawValue: rawEncoding)) else {
                return nil
            }
            return _box(_sentinel)
        }

        // MARK: - Private

        /// Small helper: map Swift sentinel → boxed Obj-C enum.
        private static func _box(_ sentinel: QsSwift.Sentinel) -> NSNumber {
            let _enum: SentinelObjC = (sentinel == .iso) ? .iso : .charset
            return NSNumber(value: _enum.rawValue)
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

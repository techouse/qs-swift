import QsSwift

/// Objective-C mirror of Swift `QsSwift.Format`.
///
/// Controls how reserved characters (especially spaces) are percent-encoded:
/// - `rfc3986` (default): spaces encoded as `%20` (modern URL standard).
/// - `rfc1738`: spaces encoded as `+` (legacy `application/x-www-form-urlencoded` style).
///
/// Raw values are stable so you can box/unbox via `NSNumber` in Obj-C.
@objc(QsFormat)
public enum FormatObjC: Int {
    case rfc3986
    case rfc1738

    /// Bridge to the Swift counterpart.
    var swift: QsSwift.Format {
        switch self {
        case .rfc3986: return .rfc3986
        case .rfc1738: return .rfc1738
        }
    }
}

// Friendly string for logs / debugging parity with Swift.
extension FormatObjC: CustomStringConvertible {
    public var description: String {
        switch self {
        case .rfc3986: return "rfc3986"
        case .rfc1738: return "rfc1738"
        }
    }
}

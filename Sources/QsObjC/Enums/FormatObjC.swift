import QsSwift

@objc(QsFormat)
public enum FormatObjC: Int {
    case rfc3986, rfc1738

    var swift: Format {
        switch self {
        case .rfc3986: return .rfc3986
        case .rfc1738: return .rfc1738
        }
    }
}

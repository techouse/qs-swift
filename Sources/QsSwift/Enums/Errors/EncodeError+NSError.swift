import Foundation

extension EncodeError: CustomNSError, LocalizedError {
    // Distinct domain for encoding errors
    public static var errorDomain: String { "io.github.techouse.qsswift.encode" }

    // Stable numeric codes
    public var errorCode: Int {
        switch self {
        case .cyclicObject: return 1
        }
    }

    // Human-friendly message (also used for NSError.localizedDescription)
    public var errorDescription: String? { description }

    // Extra info if you ever add more fields; for now just description.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: description]
    }
}

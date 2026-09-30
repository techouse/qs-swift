import Foundation

extension EncodeError: CustomNSError, LocalizedError {
  // Distinct domain for encoding errors
  public static var errorDomain: String { "io.github.techouse.qsswift.encode" }

  /// NSError user-info key containing the configured maximum serialization depth.
  public static let userInfoMaxDepthKey = "maxDepth"

  // Stable numeric codes
  public var errorCode: Int {
    switch self {
    case .cyclicObject: return 1
    case .depthExceeded: return 2
    }
  }

  // Human-friendly message (also used for NSError.localizedDescription)
  public var errorDescription: String? { description }

  // Additional metadata for errors with associated values.
  public var errorUserInfo: [String: Any] {
    switch self {
    case .cyclicObject:
      return [NSLocalizedDescriptionKey: description]
    case .depthExceeded(let maxDepth):
      return [
        NSLocalizedDescriptionKey: description,
        Self.userInfoMaxDepthKey: maxDepth,
      ]
    }
  }
}

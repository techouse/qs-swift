import Foundation
import QsSwift

/// Objective-C bridge for Swift `Delimiter` (either a literal string or a regex).
@objc(QsDelimiter)
@objcMembers
public final class DelimiterObjC: NSObject, @unchecked Sendable {
    private enum Backing: @unchecked Sendable {
        case string(QsSwift.StringDelimiter)
        case regex(QsSwift.RegexDelimiter)
    }

    private let backing: Backing

    // MARK: - Inits

    /// Use a literal string delimiter (e.g. "&", ",", ";").
    public init(string: String) {
        self.backing = .string(QsSwift.StringDelimiter(string))
    }

    /// Use a regex pattern delimiter (e.g. #"\\s*[,;]\\s*"#). Fails if the pattern is invalid.
    public init?(regexPattern pattern: String) {
        guard let rx = try? QsSwift.RegexDelimiter(pattern) else { return nil }
        self.backing = .regex(rx)
    }

    // MARK: - Presets (non-optional for convenience)

    // String presets
    public static let ampersand: DelimiterObjC = DelimiterObjC(string: "&")
    public static let comma: DelimiterObjC = DelimiterObjC(string: ",")
    public static let semicolon: DelimiterObjC = DelimiterObjC(string: ";")

    // Regex presets (known-valid → force unwrap so tests don’t need optional handling)
    public static let semicolonWithWhitespace: DelimiterObjC =
        DelimiterObjC(regexPattern: #"\s*;\s*"#)!
    public static let commaOrSemicolon: DelimiterObjC =
        DelimiterObjC(regexPattern: #"\s*[,;]\s*"#)!

    // MARK: - Bridging to Swift

    /// Expose the underlying Swift `Delimiter` for internal bridging.
    public var swift: QsSwift.Delimiter {
        switch backing {
        case .string(let s): return s
        case .regex(let r):  return r
        }
    }

    // MARK: - Convenience

    /// Split a string using the underlying delimiter (handy for tests).
    public func split(_ input: String) -> [String] {
        switch backing {
        case .string(let s):
            return s.split(input: input).map { String($0) }
        case .regex(let r):
            return r.split(input: input).map { String($0) }
        }
    }
}

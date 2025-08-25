#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Objective-C wrapper for Swift `Delimiter`.
    ///
    /// A delimiter decides how pairs are separated when parsing/encoding query
    /// strings. In Swift the core supports either a **literal string** (e.g. `"&"`,
    /// `";"`) or a **regular expression** (e.g. `#"\s*[,;]\s*"#`). This class
    /// exposes the same concept to Obj-C while keeping a tiny, allocation-free
    /// bridge back to the Swift type.
    ///
    /// - Design:
    ///   - Internally we store either a `StringDelimiter` or a `RegexDelimiter`.
    ///   - The wrapper is immutable and `@unchecked Sendable` (the underlying Swift
    ///     types are value types and thread-safe; the unchecked marker avoids
    ///     unnecessary concurrency warnings when you pass an instance across
    ///     threads from Obj-C).
    @objc(QsDelimiter)
    @objcMembers
    public final class DelimiterObjC: NSObject, @unchecked Sendable {

        // MARK: - Storage

        private enum Backing: @unchecked Sendable {
            case string(QsSwift.StringDelimiter)
            case regex(QsSwift.RegexDelimiter)
        }

        private let backing: Backing

        // MARK: - Initializers

        /// Create a delimiter from a literal string (e.g. `"&"`, `","`, `";"`).
        ///
        /// - Parameter string: The exact separator to use.
        /// - Note: This maps to the Swift `StringDelimiter`.
        public init(string: String) {
            self.backing = .string(QsSwift.StringDelimiter(string))
        }

        /// Create a delimiter from a regular-expression pattern.
        ///
        /// - Parameter pattern: A regex pattern understood by Swift Regex.
        /// - Returns: `nil` if `pattern` is invalid.
        /// - Note: This maps to the Swift `RegexDelimiter`.
        public init?(regexPattern pattern: String) {
            guard let rx = try? QsSwift.RegexDelimiter(pattern) else { return nil }
            self.backing = .regex(rx)
        }

        // MARK: - Common presets

        // String presets (non-optional for convenience in Obj-C)
        public static let ampersand = DelimiterObjC(string: "&")
        public static let comma = DelimiterObjC(string: ",")
        public static let semicolon = DelimiterObjC(string: ";")

        // Regex presets (patterns are known-valid). Avoid force unwrap to satisfy SwiftLint;
        // if construction ever fails on a future toolchain, fall back to a string delimiter.
        public static let semicolonWithWhitespace: DelimiterObjC = {
            DelimiterObjC(regexPattern: #"\s*;\s*"#) ?? DelimiterObjC(string: ";")
        }()

        public static let commaOrSemicolon: DelimiterObjC = {
            DelimiterObjC(regexPattern: #"\s*[,;]\s*"#) ?? DelimiterObjC(string: ",")
        }()

        // MARK: - Bridging to Swift

        /// Expose the underlying Swift `Delimiter` to the Swift core.
        ///
        /// This is primarily used internally by the bridge when calling into
        /// `QsSwift` APIs; you typically won’t need it from Obj-C.
        public var swift: QsSwift.Delimiter {
            switch backing {
            case .string(let sd): return sd
            case .regex(let rd): return rd
            }
        }

        // MARK: - Convenience (handy for tests)

        /// Split a string using this delimiter.
        ///
        /// - Parameter input: The string to split.
        /// - Returns: An array of components. Intended for tests and debugging.
        public func split(_ input: String) -> [String] {
            switch backing {
            case .string(let sd):
                return sd.split(input: input).map { String($0) }
            case .regex(let rd):
                return rd.split(input: input).map { String($0) }
            }
        }
    }
#endif

import Foundation

/// Splits a query string into key–value pairs using a chosen strategy.
/// - Note: Implementations should be **pure** and fast; they are called on the hot path.
public protocol Delimiter {
    /// Split `input` into parts; never return an empty array.
    func split(input: String) -> [String]
}

// MARK: - StringDelimiter

/// A fast, simple delimiter based on a literal separator (e.g. `"&"`, `","`, `";"`).
///
/// Uses `String.components(separatedBy:)`, which is highly optimized for fixed substrings.
/// Prefer this for the common querystring case (`"&"`).
public struct StringDelimiter: Delimiter, Equatable, Sendable {
    public let value: String

    public init(_ value: String) { self.value = value }

    @inlinable
    public func split(input: String) -> [String] {
        input.components(separatedBy: value)
    }
}

// MARK: - RegexDelimiter

/// A delimiter that splits on a regular expression pattern (e.g. `\\s*[,;]\\s*`).
///
/// Use this when you need whitespace-tolerant or multi-character separators.
/// Compiles the regex once and reuses it.
///
/// - Performance: Regex splitting is slower than a literal delimiter; only use it when needed.
/// - Thread-safety: `NSRegularExpression` is thread-safe on Apple platforms, but not `Sendable`.
///   We therefore mark this type `@unchecked Sendable`.
public struct RegexDelimiter: Delimiter, Equatable, @unchecked Sendable {
    public let pattern: String
    private let regex: NSRegularExpression

    /// Compiles the pattern. Throws if the pattern is invalid.
    public init(_ pattern: String) throws {
        self.pattern = pattern
        self.regex = try NSRegularExpression(pattern: pattern, options: [])
    }

    /// Split using the compiled regex, converting `NSRange` (UTF-16) to `String.Index` safely.
    ///
    /// - Important: We **must** convert via UTF-16 indices; using `offsetBy:` with `NSRange.location`
    ///   can break on extended grapheme clusters (emoji, diacritics).
    public func split(input: String) -> [String] {
        let full = NSRange(input.startIndex..<input.endIndex, in: input)
        var out: [String] = []
        var hasMatch = false
        var lastUTF16 = 0
        regex.enumerateMatches(in: input, options: [], range: full) { match, _, _ in
            guard let match else { return }
            hasMatch = true
            let range = match.range
            if range.length == 0 { return }  // keep the zero-width guard if adopted
            if range.location >= lastUTF16 {
                let start = String.Index(utf16Offset: lastUTF16, in: input)
                let end = String.Index(utf16Offset: range.location, in: input)
                out.append(String(input[start..<end]))
            }
            lastUTF16 = range.location + range.length
        }
        if !hasMatch { return [input] }

        // Trailing remainder, allow empty when delimiter is at the end to match components(separatedBy:)
        let utf16Count = input.utf16.count
        if lastUTF16 <= utf16Count {
            let start = String.Index(utf16Offset: lastUTF16, in: input)
            out.append(String(input[start...]))
        }

        // Never return an empty array
        return out.isEmpty ? [""] : out
    }

    public static func == (lhs: RegexDelimiter, rhs: RegexDelimiter) -> Bool {
        lhs.pattern == rhs.pattern
    }
}

// MARK: - Convenience presets

extension StringDelimiter {
    /// `&` — the standard querystring separator.
    public static let ampersand = StringDelimiter("&")
    /// `,` — simple comma-separated values.
    public static let comma = StringDelimiter(",")
    /// `;` — semicolon-separated values.
    public static let semicolon = StringDelimiter(";")
}

extension RegexDelimiter {
    /// Compile a built-in regex pattern for a preset. These patterns are hard-coded
    /// and expected to be valid; if not, we fail fast with a clear message.
    @inline(__always)
    private static func _compileOrCrash(_ pattern: String) -> RegexDelimiter {
        do {
            return try RegexDelimiter(pattern)
        } catch {
            preconditionFailure("Invalid built-in delimiter regex: \(pattern) — \(type(of: error)): \(error)")
        }
    }

    /// Splits on `;` with optional surrounding whitespace.
    public static let semicolonWithWhitespace: RegexDelimiter = _compileOrCrash(#"\s*;\s*"#)

    /// Splits on `,` **or** `;`, each with optional surrounding whitespace.
    public static let commaOrSemicolon: RegexDelimiter = _compileOrCrash(#"\s*[,;]\s*"#)
}

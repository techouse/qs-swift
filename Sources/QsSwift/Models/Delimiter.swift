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
        let matches = regex.matches(in: input, options: [], range: full)

        // Fast path: no matches → return the whole string
        guard !matches.isEmpty else { return [input] }

        var out: [String] = []
        out.reserveCapacity(matches.count + 1)

        var lastUTF16 = 0
        for match in matches {
            let range = match.range
            // Append slice from last end → start of this match (if any)
            if range.location > lastUTF16 {
                let start = String.Index(utf16Offset: lastUTF16, in: input)
                let end = String.Index(utf16Offset: range.location, in: input)
                out.append(String(input[start..<end]))
            }
            lastUTF16 = range.location + range.length
        }

        // Trailing remainder, if any
        if lastUTF16 < input.utf16.count {
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
            preconditionFailure("Invalid built-in delimiter regex: \(pattern). Error: \(error)")
        }
    }

    /// Splits on `;` with optional surrounding whitespace.
    public static let semicolonWithWhitespace: RegexDelimiter = _compileOrCrash(#"\s*;\s*"#)

    /// Splits on `,` **or** `;`, each with optional surrounding whitespace.
    public static let commaOrSemicolon: RegexDelimiter = _compileOrCrash(#"\s*[,;]\s*"#)
}

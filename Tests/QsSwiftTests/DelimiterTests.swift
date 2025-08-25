import Foundation
import Testing

@testable import QsSwift

struct DelimiterTests {
    /// Canonical cases that mirror `String.components(separatedBy:)` semantics
    /// (i.e. include empty fields between adjacent delimiters and at the end).
    private static let cases: [(input: String, expected: [String])] = [
        ("", [""]),
        (";", ["", ""]),
        ("a;;b", ["a", "", "b"]),
        (";a;", ["", "a", ""]),
        (";a;", ["", "a", ""]),
        (";;", ["", "", ""]),
        ("a;;", ["a", "", ""]),
        (";;a", ["", "", "a"]),
    ]

    @Test("String delimiter ';' includes empty segments like components(separatedBy:)")
    func stringDelimiterIncludesEmptySegments() throws {
        let delim = StringDelimiter(";")
        for (s, expected) in Self.cases {
            let got = delim.split(input: s)
            #expect(got == expected, "split(\"\(s)\") with string delimiter")
        }
    }

    @Test("Regex delimiter ';' includes empty segments like components(separatedBy:)")
    func regexDelimiterIncludesEmptySegments() throws {
        #expect(throws: Never.self) {
            _ = try RegexDelimiter(";")
        }
        let delim = try RegexDelimiter(";")
        for (s, expected) in Self.cases {
            let got = delim.split(input: s)
            #expect(got == expected, "split(\"\(s)\") with regex delimiter")
        }
    }

    @Test("Unicode graphemes and presets behave like components(separatedBy:)")
    func unicodeAndPresets() throws {
        // Extended grapheme clusters
        let family = "👨‍👩‍👧‍👦"  // multi-scalar emoji
        let flags = "🇺🇸,🇨🇦"

        // Regex delimiter on semicolon
        let r = try RegexDelimiter(#"\s*;\s*"#)
        #expect(r.split(input: "\(family);\(family)") == [family, family])
        #expect(r.split(input: "\(family);") == [family, ""])

        // Presets
        #expect(RegexDelimiter.semicolonWithWhitespace.split(input: "a ; b") == ["a", "b"])
        #expect(RegexDelimiter.commaOrSemicolon.split(input: "a, b; c") == ["a", "b", "c"])

        // Literal delimiter with graphemes
        let s = StringDelimiter(";")
        #expect(s.split(input: "\(family);\(family)") == [family, family])
    }
}

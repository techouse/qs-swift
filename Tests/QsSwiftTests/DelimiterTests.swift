

import Foundation
import Testing
@testable import QsSwift

struct DelimiterTests {
    /// Canonical cases that mirror `String.components(separatedBy:)` semantics
    /// (i.e. include empty fields between adjacent delimiters and at the end).
    private static let cases: [(input: String, expected: [String])] = [
        ("", [""] ),
        (";", ["", ""]),
        ("a;;b", ["a", "", "b"]),
        (";a;", ["", "a", ""])
    ]

    @Test("String delimiter ';' includes empty segments like components(separatedBy:)")
    func stringDelimiterIncludesEmptySegments() throws {
        let delim = StringDelimiter(";")
        for (s, expected) in Self.cases {
            let got = delim.split(input: s).map { String($0) }
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
            let got = delim.split(input: s).map { String($0) }
            #expect(got == expected, "split(\"\(s)\") with regex delimiter")
        }
    }
}

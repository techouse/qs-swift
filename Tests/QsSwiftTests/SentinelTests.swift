@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct SentinelTests {
    @Test("Sentinel.iso - value, encoded, and description")
    func testSentinelISO() async throws {
        #expect(Sentinel.iso.value == "&#10003;")
        #expect(Sentinel.iso.encoded == "utf8=%26%2310003%3B")

        // description should mirror `encoded`
        #expect(Sentinel.iso.description == "utf8=%26%2310003%3B")

        // Interpolation should use description
        let interpolated = "\(Sentinel.iso)"
        #expect(interpolated == "utf8=%26%2310003%3B")

        // String descrribing test
        let stringDescription = String(describing: Sentinel.iso)
        #expect(stringDescription == Sentinel.iso.encoded)
    }

    @Test("Sentinel.charset - value, encoded, and description")
    func testSentinelCharset() async throws {
        #expect(Sentinel.charset.value == "✓")
        #expect(Sentinel.charset.encoded == "utf8=%E2%9C%93")

        // description should mirror `encoded`
        #expect(Sentinel.charset.description == "utf8=%E2%9C%93")

        // Interpolation should use description
        let interpolated = "\(Sentinel.charset)"
        #expect(interpolated == Sentinel.charset.encoded)

        // String describing test
        let stringDescription = String(describing: Sentinel.charset)
        #expect(stringDescription == "utf8=%E2%9C%93")
    }

    @Test("Sentinel - sanity: iso and charset differ")
    func testSentinelDiffer() async throws {
        #expect(Sentinel.iso.value != Sentinel.charset.value)
        #expect(Sentinel.iso.encoded != Sentinel.charset.encoded)
    }

    @Test("Sentinel.match exact and case-insensitive variants")
    func sentinel_match_variants() {
        // Exact matches
        #expect(Sentinel.match(encodedPart: Sentinel.charsetString) == .charset)
        #expect(Sentinel.match(encodedPart: Sentinel.isoString) == .iso)
        #expect(Sentinel.match(encodedPart: "UTF8=%E2%9C%93") == nil)  // default is strict

        // Case-insensitive: uppercased key and hex
        #expect(Sentinel.match(encodedPart: "UTF8=%e2%9c%93", caseInsensitive: true) == .charset)
        #expect(Sentinel.match(encodedPart: "utf8=%26%2310003%3b", caseInsensitive: true) == .iso)

        // Non-matching noise
        #expect(Sentinel.match(encodedPart: "foo=utf8=%E2%9C%93", caseInsensitive: true) == nil)
    }
    @Test("Sentinel ASCII-folding semantics")
    func test_ascii_folding_semantics() {
        #if DEBUG
            // Non-letters should not be folded: '[' (0x5B) vs '{' (0x7B)
            #expect(Sentinel.__test_asciiEquals("[", "{") == false)
            #expect(Sentinel.__test_asciiEquals("{", "[") == false)

            // ASCII letters should compare case-insensitively across the whole string.
            #expect(Sentinel.__test_asciiEquals("UTF8=%E2%9C%93", "utf8=%e2%9c%93") == true)

            // Letters fold; digits/punctuation remain exact.
            #expect(Sentinel.__test_asciiEquals("A0Zz", "a0zz") == true)
        #else
            // Fallback assertion through the public API when debug-only hook isn't available.
            #expect(Sentinel.match(encodedPart: "UTF8=%E2%9C%93", caseInsensitive: true) == .charset)
        #endif
    }
}

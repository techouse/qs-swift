@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct FormatTests {
    @Test("Format.description returns readable labels")
    func format_description_labels() {
        #expect(String(describing: Format.rfc3986) == "rfc3986")
        #expect(Format.rfc1738.description == "rfc1738")
    }

    @Test("Format.formatter applies RFC3986/1738 post-processing")
    func format_formatter_behaviour() {
        let encoded = "a%20b%20c"

        // RFC3986: no change
        #expect(Format.rfc3986.formatter.apply(encoded) == "a%20b%20c")

        // RFC1738: %20 → +
        #expect(Format.rfc1738.formatter.apply(encoded) == "a+b+c")
    }
}

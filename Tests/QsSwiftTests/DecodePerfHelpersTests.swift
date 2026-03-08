import Foundation
import QsTestSupport

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct DecodePerfHelpersTests {
    @Test("parseDecodeBenchOutput parses Swift and ObjC snapshot lines")
    func parseDecodeBenchOutput_parsesLines() throws {
        let output = """
              swift-decode C1 count=100 comma=false utf8=false len=8: 0.123 ms/op | keys=100
              objc-decode C3 count=1000 comma=true utf8=true len=40: 0.456 ms/op | keys=1001
            """

        let parsed = try parseDecodeBenchOutput(output)
        let swiftKey = DecodeBenchCaseKey(
            runtime: "swift", name: "C1", count: 100, comma: false, utf8: false, len: 8, keys: 100)
        let objcKey = DecodeBenchCaseKey(
            runtime: "objc", name: "C3", count: 1000, comma: true, utf8: true, len: 40, keys: 1001)

        #expect(parsed[swiftKey] == 0.123)
        #expect(parsed[objcKey] == 0.456)
    }

    @Test("decode snapshot baseline includes all Swift decode cases")
    func loadDecodeBaseline_containsSwiftCases() throws {
        let baseline = try loadDecodeBaseline(runtime: "swift")
        for c in decodePerfCases {
            let key = DecodeBenchCaseKey(
                runtime: "swift",
                name: c.name,
                count: c.count,
                comma: c.comma,
                utf8: c.utf8,
                len: c.len,
                keys: c.keys
            )
            #expect(baseline[key] != nil, "missing baseline for \(c.name)")
        }
    }
}

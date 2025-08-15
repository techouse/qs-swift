#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    @testable import QsObjC
    @testable import QsSwift

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    @Suite("objc-sentinel")
    struct ObjCSentinelTests {

        @Test("Sentinel.iso - value, encoded, and description")
        func testISO() throws {
            #expect(QsObjC.SentinelObjC.iso.value == "&#10003;")
            #expect(QsObjC.SentinelObjC.iso.encoded == "utf8=%26%2310003%3B")

            // description (via CustomStringConvertible) should mirror `encoded`
            #expect(String(describing: QsObjC.SentinelObjC.iso) == "utf8=%26%2310003%3B")

            // Sanity: matches Swift core type
            #expect(QsObjC.SentinelObjC.iso.encoded == QsSwift.Sentinel.iso.encoded)
        }

        @Test("Sentinel.charset - value, encoded, and description")
        func testCharset() throws {
            #expect(QsObjC.SentinelObjC.charset.value == "✓")
            #expect(QsObjC.SentinelObjC.charset.encoded == "utf8=%E2%9C%93")

            // description should mirror `encoded`
            #expect(String(describing: QsObjC.SentinelObjC.charset) == "utf8=%E2%9C%93")

            // Sanity: matches Swift core type
            #expect(QsObjC.SentinelObjC.charset.encoded == QsSwift.Sentinel.charset.encoded)
        }

        @Test("Sentinel - sanity: iso and charset differ")
        func testDiffer() throws {
            #expect(QsObjC.SentinelObjC.iso.value != QsObjC.SentinelObjC.charset.value)
            #expect(QsObjC.SentinelObjC.iso.encoded != QsObjC.SentinelObjC.charset.encoded)
        }
    }
#endif

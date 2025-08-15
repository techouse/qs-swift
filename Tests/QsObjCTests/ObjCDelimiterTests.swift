#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    @testable import QsObjC
    #if canImport(Testing)
        import Testing
    #endif

    struct ObjCDelimiterTests {
        @Test("StringDelimiterObjC splits on ampersand")
        func stringDelimiter_split() throws {
            let d = DelimiterObjC.ampersand
            let parts = d.split("a=b&c=d")
            #expect(parts == ["a=b", "c=d"])
        }

        @Test("RegexDelimiterObjC splits on semicolon with whitespace")
        func regexDelimiter_split() throws {
            let d = DelimiterObjC.semicolonWithWhitespace
            let parts = d.split("a=b ; c=d; e=f ")
            #expect(parts == ["a=b", "c=d", "e=f "])
        }

        @Test("DelimiterObjC type erasure works for string delimiter")
        func delimiterObjC_string() throws {
            let d = DelimiterObjC.comma
            let parts = d.split("a=b,c=d")
            #expect(parts == ["a=b", "c=d"])
        }
    }
#endif

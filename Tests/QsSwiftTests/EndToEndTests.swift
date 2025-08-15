import Foundation

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct EndToEndTests {
    @Test("e2e: data <-> encoded (parametrized)")
    func e2e_parametrized_encode_decode_roundtrip() throws {
        for (i, element) in endToEndTestCases().enumerated() {
            let gotEncoded = try Qs.encode(element.data, options: .init(encode: false))
            #expect(
                gotEncoded == element.encoded,
                "encode mismatch [case \(i)]:\nEXPECTED: \(element.encoded)\nENCODED: \(gotEncoded)"
            )

            let gotDecoded = try Qs.decode(element.encoded)
            // compare maps in a container-agnostic way
            #expect(
                deepEqual(element.data, gotDecoded),
                "decode mismatch [case \(i)]:\nENCODED: \(element.encoded)\nEXPECTED: \(String(describing: normalizeToStdDict(element.data)))\nDECODED: \(gotDecoded)"
            )
        }
    }
}

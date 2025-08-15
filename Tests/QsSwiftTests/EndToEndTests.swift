import Foundation
import OrderedCollections

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

// Recursively turn OrderedDictionary → [String: Any], and also normalize
// any nested [String: Any] / arrays so NSDictionary equality works deeply.
private func normalizeToStdDict(_ value: Any) -> Any {
    if let od = value as? OrderedDictionary<String, Any> {
        var out: [String: Any] = [:]
        out.reserveCapacity(od.count)
        for (k, v) in od {
            out[k] = normalizeToStdDict(v)
        }
        return out
    }
    if let dict = value as? [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict {
            out[k] = normalizeToStdDict(v)
        }
        return out
    }
    if let arr = value as? [Any] {
        return arr.map(normalizeToStdDict)
    }
    return value
}

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

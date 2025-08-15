#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import OrderedCollections

    @testable import QsObjC

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    struct EndToEndObjCTests {
        @Test("e2e ObjC: data <-> encoded (parametrized)")
        func e2e_parametrized_encode_decode_roundtrip_objc() throws {
            for (i, element) in endToEndTestCasesObjC().enumerated() {
                // Encode with encode=false to match the expected literal strings
                let opts = EncodeOptionsObjC()
                opts.encode = false

                let gotEncoded =
                    try #require(QsBridge.encode(element.data, options: opts)) as String
                #expect(
                    gotEncoded == (element.encoded as String),
                    "encode mismatch [case \(i)]:\nEXPECTED: \(element.encoded)\nENCODED: \(gotEncoded)"
                )

                let gotDecoded = try #require(QsBridge.decode(element.encoded as NSString))
                #expect(
                    deepEqualObjC(element.data, gotDecoded),
                    """
                    decode mismatch [case \(i)]:
                    ENCODED: \(element.encoded)
                    EXPECTED: \(normalizeStd(element.data))
                    DECODED: \(gotDecoded)
                    """
                )
            }
        }
    }

    // MARK: - Minimal container-normalization for equality

    private func normalizeStd(_ any: Any) -> Any {
        switch any {
        case let od as OrderedDictionary<NSString, Any>:
            var out: [String: Any] = [:]
            out.reserveCapacity(od.count)
            for (k, v) in od { out[k as String] = normalizeStd(v) }
            return out
        case let od as OrderedDictionary<String, Any>:
            var out: [String: Any] = [:]
            out.reserveCapacity(od.count)
            for (k, v) in od { out[k] = normalizeStd(v) }
            return out
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict { out[k] = normalizeStd(v) }
            return out
        case let dict as [AnyHashable: Any]:
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict { out[String(describing: k)] = normalizeStd(v) }
            return out
        case let arr as [Any]:
            return arr.map { normalizeStd($0) }
        default:
            return any
        }
    }

    private func deepEqualObjC(_ lhs: Any, _ rhs: Any) -> Bool {
        let nl = normalizeStd(lhs)
        let nr = normalizeStd(rhs)
        if let dl = nl as? [String: Any], let dr = nr as? [String: Any] {
            return NSDictionary(dictionary: dl).isEqual(to: dr)
        }
        if let al = nl as? [Any], let ar = nr as? [Any] {
            return NSArray(array: al).isEqual(to: ar)
        }
        return (nl as AnyObject) === (nr as AnyObject)
            || String(describing: nl) == String(describing: nr)
    }
#endif

import Foundation
import OrderedCollections

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct EncoderInternalsTests {
    @Test("KeyPathNode caches dot/materialized paths and keeps append semantics")
    func keyPathNode_cachesMaterializedAndDotEncoded() {
        let root = KeyPathNode.fromMaterialized("user.name")
        #expect(root.append("") === root)

        let nested = root.append("[first.last]").append("[0]")
        #expect(nested.materialize() == "user.name[first.last][0]")

        let dotEncoded1 = nested.asDotEncoded()
        let dotEncoded2 = nested.asDotEncoded()
        #expect(dotEncoded1 === dotEncoded2)
        #expect(dotEncoded1.materialize() == "user%2Ename[first%2Elast][0]")
    }

    @Test("KeyPathNode identity dot-encoding does not self-retain")
    func keyPathNode_identityDotEncoding_noSelfRetain() {
        weak var weakNode: KeyPathNode?

        do {
            let node = KeyPathNode.fromMaterialized("root").append("[k]").append("[str]")
            #expect(node.asDotEncoded() === node)
            #expect(node.asDotEncoded() === node)
            weakNode = node
        }

        #expect(weakNode == nil)
    }

    @Test("Encoder iterative traversal parity for mixed map/list/scalar payloads")
    func encoder_iterativeTraversalParity_mixedPayload() throws {
        var nestedObject = OrderedDictionary<String, Any>()
        nestedObject["arr"] = [1, NSNull(), OrderedDictionary<String, Any>(uniqueKeysWithValues: [("x", "y")])]
        nestedObject["str"] = "v"

        var payload = OrderedDictionary<String, Any>()
        payload["k"] = nestedObject
        payload["n"] = 3

        let any = try Encoder.encode(
            data: payload,
            undefined: false,
            sideChannel: NSMapTable<AnyObject, AnyObject>.weakToWeakObjects(),
            prefix: "root",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 0
        )

        let out =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)

        #expect(out == "root[k][str]=v&root[k][arr][0]=1&root[k][arr][1]=&root[k][arr][2][x]=y&root[n]=3")
    }

    @Test("Encoder linear-chain fast path falls back when allowDots is enabled")
    func encoder_linearChainFastPath_fallback_allowDots() throws {
        let payload: [String: Any] = ["a": ["leaf": "x"]]

        let any = try Encoder.encode(
            data: payload,
            undefined: false,
            sideChannel: NSMapTable<AnyObject, AnyObject>.weakToWeakObjects(),
            prefix: "root",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: true,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 0
        )

        let out =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)

        #expect(out == "root.a.leaf=x")
    }
}

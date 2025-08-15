import Foundation
import OrderedCollections

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct EncodeTopLevelNormalizationTests {

    // 1) OrderedDictionary<NSString, Any> → preserves insertion order, keys normalized to String
    @Test("encode: OrderedDictionary<NSString, Any> preserves order")
    func encode_orderedDict_NSString_keys_preserve_order() throws {
        var od: OrderedDictionary<NSString, Any> = [:]
        od["b" as NSString] = "2"
        od["a" as NSString] = "1"

        let got = try Qs.encode(od, options: .init(encode: false))
        #expect(got == "b=2&a=1")

        let decoded = try Qs.decode(got)
        #expect(NSDictionary(dictionary: decoded).isEqual(to: ["b": "2", "a": "1"]))
    }

    // 2) OrderedDictionary<AnyHashable, Any> with mixed key types → stringified, insertion order kept
    @Test("encode: OrderedDictionary<AnyHashable, Any> stringifies keys, preserves order")
    func encode_orderedDict_anyHashable_keys_stringified() throws {
        var od: OrderedDictionary<AnyHashable, Any> = [:]
        od[1] = "one"
        od["a"] = "alpha"
        od[2] = "two"
        od["b"] = "beta"

        let got = try Qs.encode(od, options: .init(encode: false))
        #expect(got == "1=one&a=alpha&2=two&b=beta")

        let decoded = try Qs.decode(got)
        #expect(
            NSDictionary(dictionary: decoded).isEqual(to: [
                "1": "one", "a": "alpha", "2": "two", "b": "beta",
            ])
        )
    }

    // 3) NSDictionary top-level: round-trip equality without assuming enumeration order
    @Test("encode: NSDictionary round-trips (unordered), and can be sorted deterministically")
    func encode_nsDictionary_roundtrip_and_sorted() throws {
        let nd: NSDictionary = ["b": "2", "a": "1", "c": "3"]

        // (a) Order-agnostic round-trip
        let got = try Qs.encode(nd, options: .init(encode: false))
        let rt = try Qs.decode(got)
        #expect(NSDictionary(dictionary: rt).isEqual(to: ["a": "1", "b": "2", "c": "3"]))

        // (b) Deterministic string with explicit sorter
        let sorted = try Qs.encode(
            nd,
            options: .init(
                encode: false,
                sort: { a, b in
                    let sa = a.map { String(describing: $0) } ?? ""
                    let sb = b.map { String(describing: $0) } ?? ""
                    if sa == sb { return 0 }
                    return sa < sb ? -1 : 1
                }
            )
        )
        #expect(sorted == "a=1&b=2&c=3")
    }

    // 4) [AnyHashable: Any] top-level: same as NSDictionary path
    @Test("encode: [AnyHashable: Any] round-trips and supports explicit sort")
    func encode_anyHashable_dict_roundtrip_and_sorted() throws {
        let m: [AnyHashable: Any] = ["b": "2", "a": "1", "c": "3"]

        let got = try Qs.encode(m, options: .init(encode: false))
        let rt = try Qs.decode(got)
        #expect(NSDictionary(dictionary: rt).isEqual(to: ["a": "1", "b": "2", "c": "3"]))

        let sorted = try Qs.encode(
            m,
            options: .init(
                encode: false,
                sort: { a, b in
                    let sa = a.map { String(describing: $0) } ?? ""
                    let sb = b.map { String(describing: $0) } ?? ""
                    if sa == sb { return 0 }
                    return sa < sb ? -1 : 1
                }
            )
        )
        #expect(sorted == "a=1&b=2&c=3")
    }

    // 5) [Any] top-level: promoted to {"0":..., "1":...}
    @Test("encode: top-level Array promoted to string-indexed object")
    func encode_array_top_level_promoted_to_indices() throws {
        let arr: [Any] = ["x", "y"]

        let got = try Qs.encode(arr, options: .init(encode: false))
        #expect(got == "0=x&1=y")

        let decoded = try Qs.decode(got)
        #expect(NSDictionary(dictionary: decoded).isEqual(to: ["0": "x", "1": "y"]))
    }

    // 6) NSNull handling via NSDictionary: strict vs non-strict nulls
    @Test("encode: NSDictionary(NSNull) respects strictNullHandling (a vs a=)")
    func encode_nsDictionary_nsnull_behavior() throws {
        let nd: NSDictionary = ["a": NSNull()]

        let strict = try Qs.encode(nd, options: .init(encode: false, strictNullHandling: true))
        #expect(strict == "a")

        let lax = try Qs.encode(nd, options: .init(encode: false, strictNullHandling: false))
        #expect(lax == "a=")
    }

    // 7) Default deterministic top-level sort when encode == true (no custom sort)
    //    Non-empty keys sorted A→Z; empty keys go to the end.
    @Test("encode: default top-level sort when encode == true")
    func encode_default_sort_when_encode_true() throws {
        var od: OrderedDictionary<String, Any> = [:]
        od["b"] = "1"
        od[""] = "0"
        od["a"] = "2"

        let got = try Qs.encode(od, options: .init(encode: true))
        #expect(got == "a=2&b=1&=0")
    }
}

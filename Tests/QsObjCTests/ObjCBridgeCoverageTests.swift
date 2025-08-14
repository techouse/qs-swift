#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
import Foundation

@testable import QsObjC

#if canImport(Testing)
import Testing
#else
#error("The swift-testing package is required to build tests on Swift 5.x")
#endif

@Suite("ObjC Bridge coverage")
struct ObjCBridgeCoverageTests {

    // MARK: - bridgeInputForDecode

    @Test("bridgeInputForDecode: NSString → Swift.String")
    func decode_nsstring_becomes_swift_string() {
        let out = QsBridge.bridgeInputForDecode("abc" as NSString)
        #expect(out is String)
        #expect(out as? String == "abc")
    }

    @Test("bridgeInputForDecode forced-reduce preserves ObjC key (reduce branch hit)")
    func decode_force_reduce_preserves_objc_key() {
        final class WeirdKey: NSObject, NSCopying {
            func copy(with zone: NSZone? = nil) -> Any { self }
            override var description: String { "WeirdKey" }
        }

        let key = WeirdKey()
        let dict = NSMutableDictionary()
        dict[key] = "v"

        // Opt in to the reduce(into:) fallback branch
        let bridged = QsBridge.bridgeInputForDecode(dict, forceReduce: true)
        let out = bridged as? [AnyHashable: Any]

        #expect(out != nil && out?.count == 1)
        // Because NSObject is Hashable in Swift, the inner cast succeeds and the key remains `key`.
        #expect(out?[AnyHashable(key)] as? String == "v")
    }

    @Test("bridgeInputForDecode: NSDictionary that *is* [AnyHashable:Any] passes through cast")
    func decode_dictionary_already_hashable_keys() {
        let d: NSDictionary = [NSNumber(value: 42): "answer", "k": "v"]
        // No forceReduce → we should take the 'as? [AnyHashable: Any]' path
        let bridged = QsBridge.bridgeInputForDecode(d)
        let out = bridged as? [AnyHashable: Any]
        #expect(out? [42] as? String == "answer")
        #expect(out? ["k"] as? String == "v")
    }

    @Test("bridgeInputForDecode: NSArray → [Any]")
    func decode_nsarray_maps_to_swift_array() {
        let a: NSArray = ["x" as NSString, NSNumber(value: 42), NSNull()]
        let bridged = QsBridge.bridgeInputForDecode(a)
        let arr = bridged as? [Any]
        #expect(arr?.count == 3)

        let s0 = (arr?[0] as? String) ?? (arr?[0] as? NSString).map(String.init)
        #expect(s0 == "x")
        #expect((arr?[1] as? NSNumber)?.intValue == 42)
        #expect(arr?[2] is NSNull)
    }

    @Test("bridgeInputForDecode: pass-through for NSNumber / NSNull")
    func decode_passthrough_scalars() {
        let num: Any? = NSNumber(value: 7)
        let nul: Any? = NSNull()

        let outNum = QsBridge.bridgeInputForDecode(num)
        let outNull = QsBridge.bridgeInputForDecode(nul)

        #expect((outNum as? NSNumber)?.intValue == 7)
        #expect(outNull is NSNull)
    }

    // MARK: - bridgeInputForEncode

    @Test("bridgeInputForEncode: NSString → Swift.String")
    func encode_nsstring_becomes_swift_string() {
        let out = QsBridge.bridgeInputForEncode("abc" as NSString)
        #expect(out is String)
        #expect(out as? String == "abc")
    }

    @Test("bridgeInputForEncode: NSDictionary stringifies *all* keys")
    func encode_dictionary_keys_stringified() {
        let d: NSDictionary = [NSNumber(value: 7): "v", "k": "w"]
        let bridged = QsBridge.bridgeInputForEncode(d)
        let out = bridged as? [String: Any]
        #expect(out?["7"] as? String == "v")
        #expect(out?["k"] as? String == "w")
    }

    @Test("bridgeInputForEncode: NSArray → [Any]")
    func encode_nsarray_maps_to_swift_array() {
        let a: NSArray = [NSNumber(value: 1), "z" as NSString]
        let bridged = QsBridge.bridgeInputForEncode(a)
        let arr = bridged as? [Any]
        #expect(arr?.count == 2)
        #expect((arr?[0] as? NSNumber)?.intValue == 1)
        let s1 = (arr?[1] as? String) ?? (arr?[1] as? NSString).map(String.init)
        #expect(s1 == "z")
    }

    // MARK: - _bridgeUndefined via encode() (private helper exercised transitively)

    @Test("encode: UndefinedObjC is bridged to Swift sentinel and omitted")
    func encode_undefined_objc_omitted() {
        let d: NSDictionary = ["a": UndefinedObjC()]
        var err: NSError?
        let s = QsBridge.encode(d, options: nil, error: &err)
        #expect(err == nil)
        #expect(s as String? == "")  // no pairs produced
    }

    @Test("encode: NSDictionary cycle surfaces as EncodeError.cyclicObject (no crash)")
    func encode_dictionary_cycle_maps_to_error() {
        let m = NSMutableDictionary()
        m["self"] = m  // cycle
        var err: NSError?
        let s = QsBridge.encode(m, options: nil, error: &err)
        #expect(s == nil)
        #expect(err != nil)
        #expect(err!.domain == EncodeErrorInfoObjC.domain)
        #expect(EncodeErrorObjC.kind(from: err!) == .cyclicObject)
    }

    @Test("encode: NSArray cycle surfaces as EncodeError.cyclicObject (no crash)")
    func encode_array_cycle_maps_to_error() {
        let a = NSMutableArray()
        a.add(a)  // self-cycle
        var err: NSError?
        let s = QsBridge.encode(a, options: nil, error: &err)
        #expect(s == nil)
        #expect(err != nil)
        #expect(err!.domain == EncodeErrorInfoObjC.domain)
        #expect(EncodeErrorObjC.kind(from: err!) == .cyclicObject)
    }
}
#endif

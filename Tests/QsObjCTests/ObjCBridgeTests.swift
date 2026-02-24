#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import OrderedCollections
    import Testing

    @testable import QsObjC
    @testable import QsSwift

    struct ObjCBridgeTests {
        @Test("encode → decode round-trip (flat)")
        func roundtripFlat() throws {
            let input: NSDictionary = [
                "a": "1",
                "b": "two",
            ]

            // encode is non-throwing and returns NSString?
            let qs = QsBridge.encode(input)
            #expect(qs != nil)
            guard let qs else { return }  // stop if encode failed

            // decode takes non-optional NSString and throws
            var err: NSError?
            guard let output = QsBridge.decode(qs, error: &err) else {
                #expect(err == nil)  // will fail and surface the NSError
                return
            }

            #expect(((output["a"] as? String) ?? "") == "1")
            #expect(((output["b"] as? String) ?? "") == "two")
        }

        @Test("encode → decode round-trip (nested & list)")
        func roundtripNested() throws {
            let input: NSDictionary = [
                "user": [
                    "name": "alice",
                    "meta": ["id": "42"],
                ],
                "list": ["1", "2", "3"],
            ]

            let qs = QsBridge.encode(input)
            #expect(qs != nil)
            guard let qs else { return }

            var err: NSError?
            guard let output = QsBridge.decode(qs, error: &err) else {
                #expect(err == nil)  // will fail and surface the NSError
                return
            }

            let user = output["user"] as? NSDictionary
            #expect(((user?["name"] as? String) ?? "") == "alice")

            let meta = user?["meta"] as? NSDictionary
            #expect(((meta?["id"] as? String) ?? "") == "42")

            let list = output["list"] as? [Any]
            #expect((list?.count ?? 0) == 3)
            #expect(((list?[0] as? String) ?? "") == "1")
            #expect(((list?[1] as? String) ?? "") == "2")
            #expect(((list?[2] as? String) ?? "") == "3")
        }

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
                func copy(with zone: NSZone? = nil) -> Any {
                    self
                }

                override var description: String {
                    "WeirdKey"
                }
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
            #expect(out?[42] as? String == "answer")
            #expect(out?["k"] as? String == "v")
        }

        @Test("bridgeInputForDecode: NSDictionary stringifies non-AnyHashable keys when not forcing reduce")
        func decode_dictionary_stringifies_nonHashable_keys() {
            let arrayKey: NSArray = ["k"]
            let dict = NSMutableDictionary()
            dict[arrayKey] = "value"

            let bridged = QsBridge.bridgeInputForDecode(dict)

            if let out = bridged as? [AnyHashable: Any] {
                #expect(out.count == 1)
                let firstKeyDescription = out.keys.first.map { String(describing: $0) } ?? ""
                #expect(firstKeyDescription.contains("k"))
                #expect(out.values.first as? String == "value")
            } else {
                Issue.record("Unexpected bridged type: \(type(of: bridged))")
            }
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

            if let od = bridged as? OrderedDictionary<String, Any> {
                #expect(od["7"] as? String == "v")
                #expect(od["k"] as? String == "w")
            } else if let dict = bridged as? [String: Any] {
                #expect(dict["7"] as? String == "v")
                #expect(dict["k"] as? String == "w")
            } else {
                #expect(Bool(false), "Unexpected bridged type: \(type(of: bridged))")
            }
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

        @Test("bridgeInputForEncode: Swift [String: Any] produces OrderedDictionary")
        func encode_swiftDictionary_bridgesToOrdered() {
            let payload: [String: Any] = [
                "alpha": 1,
                "sentinel": UndefinedObjC(),
            ]

            let bridged = QsBridge.bridgeInputForEncode(payload)

            if let out = bridged as? OrderedDictionary<String, Any> {
                #expect(out["alpha"] as? Int == 1)
                #expect(out["sentinel"] is UndefinedObjC)
            } else {
                Issue.record("Unexpected bridged type: \(type(of: bridged))")
            }
        }

        @Test("bridgeInputForEncode handles Swift-only values that cannot bridge to NSDictionary")
        func encode_swiftDictionary_withSwiftOnlyValues() {
            struct SwiftOnly: CustomStringConvertible {
                let id: Int
                var description: String { "swift-\(id)" }
            }

            let payload: [String: Any] = [
                "custom": SwiftOnly(id: 1),
                "sentinel": UndefinedObjC(),
            ]

            let bridged = QsBridge.bridgeInputForEncode(payload)
            if let out = bridged as? OrderedDictionary<String, Any> {
                #expect(out["custom"] is SwiftOnly)
                #expect(out["sentinel"] is UndefinedObjC)
            } else {
                Issue.record("Swift-only dictionary branch not exercised: \(type(of: bridged))")
            }
        }

        @Test("bridgeInputForEncode: Swift [Any] bridges elements recursively")
        func encode_swiftArray_bridgesElements() {
            let payload: [Any] = [UndefinedObjC(), ["key": "value"]]
            let bridged = QsBridge.bridgeInputForEncode(payload)

            if let out = bridged as? [Any] {
                #expect(out.first is UndefinedObjC)
                let nested = out.dropFirst().first as? OrderedDictionary<String, Any>
                #expect(nested?["key"] as? String == "value")
            } else {
                Issue.record("Unexpected bridged type: \(type(of: bridged))")
            }
        }

        @Test("bridgeInputForEncode(one-pass): bridgeUndefined rewrites nested sentinels")
        func encode_bridgeInputOnePass_undefinedRewrite() {
            let payload: NSDictionary = [
                "u": UndefinedObjC(),
                "nested": [
                    "x": UndefinedObjC(),
                    "v": "1",
                ],
                "arr": [
                    UndefinedObjC(),
                    ["k": UndefinedObjC()],
                ],
            ]

            let bridged = QsBridge.bridgeInputForEncode(payload, bridgeUndefined: true)
            guard let out = bridged as? OrderedDictionary<String, Any> else {
                Issue.record("Expected OrderedDictionary<String, Any>, got \(type(of: bridged))")
                return
            }

            #expect(out["u"] is QsSwift.Undefined)

            let nested = out["nested"] as? OrderedDictionary<String, Any>
            #expect(nested?["x"] is QsSwift.Undefined)
            #expect(nested?["v"] as? String == "1")

            let arr = out["arr"] as? [Any]
            #expect(arr?.first is QsSwift.Undefined)
            let arrObj = arr?.dropFirst().first as? OrderedDictionary<String, Any>
            #expect(arrObj?["k"] is QsSwift.Undefined)
        }

        @Test("bridgeInputForEncode(one-pass): preserves Foundation cycle identity")
        func encode_bridgeInputOnePass_cycleIdentity() {
            let dict = NSMutableDictionary()
            dict["self"] = dict

            let bridged = QsBridge.bridgeInputForEncode(dict, bridgeUndefined: true)
            if let out = bridged as? OrderedDictionary<String, Any> {
                #expect((out["self"] as AnyObject?) === dict)
                return
            }

            if let out = bridged as? NSDictionary {
                #expect((out["self"] as AnyObject?) === dict)
                return
            }

            Issue.record("Unexpected bridged type: \(type(of: bridged))")
        }

        @Test("bridgeInputForEncode: OrderedDictionary<NSString, Any> normalizes keys")
        func encode_orderedDictionaryNSString_keys() {
            let od = OrderedDictionary<NSString, Any>(uniqueKeysWithValues: [
                ("one" as NSString, 1),
                ("two" as NSString, 2),
            ])

            let bridged = QsBridge.bridgeInputForEncode(od)
            let out = bridged as? OrderedDictionary<String, Any>
            #expect(out?.keys.elementsEqual(["one", "two"]) == true)
            #expect(out?["one"] as? Int == 1)
        }

        @Test("bridgeInputForEncode: OrderedDictionary<String, Any> preserves ordering")
        func encode_orderedDictionaryString_keys() {
            var od = OrderedDictionary<String, Any>()
            od["first"] = 1
            od["second"] = OrderedDictionary<NSString, Any>(uniqueKeysWithValues: [
                ("nested" as NSString, UndefinedObjC())
            ])

            let bridged = QsBridge.bridgeInputForEncode(od)

            if let out = bridged as? OrderedDictionary<String, Any> {
                #expect(out["first"] as? Int == 1)
                let nested = out["second"] as? OrderedDictionary<String, Any>
                let nestedValue = nested?["nested"]
                let unwrapped: Any?
                if let value = nestedValue {
                    let mirror = Mirror(reflecting: value)
                    unwrapped = mirror.displayStyle == .optional ? mirror.children.first?.value : value
                } else {
                    unwrapped = nil
                }
                #expect((unwrapped is UndefinedObjC) || (unwrapped is QsSwift.Undefined))
            } else {
                Issue.record("Unexpected bridged type: \(type(of: bridged))")
            }
        }

        @Test("bridgeInputForEncode: OrderedDictionary<AnyHashable, Any> stringifies mixed keys")
        func encode_orderedDictionaryAnyHashable_keys() {
            let entries: [(AnyHashable, Any)] = [
                (AnyHashable(42), "answer"),
                (AnyHashable("two"), 2),
            ]
            let od = OrderedDictionary<AnyHashable, Any>(uniqueKeysWithValues: entries)

            let bridged = QsBridge.bridgeInputForEncode(od)

            if let out = bridged as? OrderedDictionary<String, Any> {
                #expect(out["42"] as? String == "answer")
                #expect(out["two"] as? Int == 2)
            } else if let dict = bridged as? [String: Any] {
                #expect(dict["42"] as? String == "answer")
                #expect(dict["two"] as? Int == 2)
            } else if let od = bridged as? OrderedDictionary<AnyHashable, Any> {
                #expect(od[AnyHashable("42")] as? String == "answer")
                #expect(od[AnyHashable("two")] as? Int == 2)
            } else {
                Issue.record("Unexpected bridged type: \(type(of: bridged))")
            }
        }

        @Test("bridgeUndefinedPreservingOrder bridges OrderedDictionary<NSString, Any>")
        func bridgeUndefined_handlesOrderedNSStringDictionary() {
            let ordered = OrderedDictionary<NSString, Any>(uniqueKeysWithValues: [
                ("u" as NSString, UndefinedObjC())
            ])

            let bridged = QsBridge.bridgeUndefinedPreservingOrder(ordered)
            let out = bridged as? OrderedDictionary<String, Any>
            #expect(out?["u"] is QsSwift.Undefined)
        }

        @Test("bridgeUndefinedPreservingOrder bridges OrderedDictionary<AnyHashable, Any>")
        func bridgeUndefined_handlesOrderedAnyHashableDictionary() {
            let entries: [(AnyHashable, Any)] = [
                (AnyHashable("u"), UndefinedObjC()),
                (AnyHashable(7), "v"),
            ]
            let ordered = OrderedDictionary<AnyHashable, Any>(uniqueKeysWithValues: entries)

            let bridged = QsBridge.bridgeUndefinedPreservingOrder(ordered)
            guard let out = bridged as? OrderedDictionary<String, Any> else {
                Issue.record("Expected OrderedDictionary<String, Any>, got \(String(describing: bridged))")
                return
            }

            #expect(Array(out.keys) == ["u", "7"])
            #expect(out["u"] is QsSwift.Undefined)
            #expect(out["7"] as? String == "v")
        }

        @Test("bridgeUndefinedPreservingOrder replaces sentinels and keeps identity")
        func bridgeUndefined_rewritesContainers() {
            let innerArray: NSMutableArray = [UndefinedObjC()]
            innerArray.add(innerArray)  // cycle

            var ordered = OrderedDictionary<String, Any>()
            ordered["u"] = UndefinedObjC()
            ordered["array"] = innerArray

            let bridged = QsBridge.bridgeUndefinedPreservingOrder(ordered)
            let out = bridged as? OrderedDictionary<String, Any>
            #expect(out?["u"] is QsSwift.Undefined)

            let bridgedArray = out?["array"] as? [Any]
            #expect(bridgedArray?.first is QsSwift.Undefined)
            #expect((bridgedArray?[1] as AnyObject?) === innerArray)
        }

        @Test("bridgeUndefinedPreservingOrder bridges NSDictionary values")
        func bridgeUndefined_handlesNSDictionary() {
            let dict: NSDictionary = [
                "u": UndefinedObjC(),
                "value": "v",
            ]

            let bridged = QsBridge.bridgeUndefinedPreservingOrder(dict)
            let out = bridged as? OrderedDictionary<String, Any>
            #expect(out?["u"] is QsSwift.Undefined)
            #expect(out?["value"] as? String == "v")
        }

        @Test("bridgeUndefinedPreservingOrder handles Swift dictionaries and arrays without ObjC bridging")
        func bridgeUndefined_swiftContainersNoObjCBridge() {
            var seen = Set<ObjectIdentifier>()
            let swiftDict: [String: Any] = [
                "value": 42,
                "sentinel": UndefinedObjC(),
            ]

            if let bridgedDict = QsBridge._bridgeUndefinedPreservingOrder(swiftDict, seen: &seen)
                as? OrderedDictionary<String, Any>
            {
                #expect(bridgedDict["value"] as? Int == 42)
                #expect(bridgedDict["sentinel"] is QsSwift.Undefined)
            } else {
                Issue.record("Swift dictionary branch not exercised")
            }

            let swiftArray: [Any] = ["first", UndefinedObjC()]
            seen.removeAll()
            if let bridgedArray = QsBridge._bridgeUndefinedPreservingOrder(swiftArray, seen: &seen) as? [Any] {
                #expect(bridgedArray[0] as? String == "first")
                #expect(bridgedArray[1] is QsSwift.Undefined)
            } else {
                Issue.record("Swift array branch not exercised")
            }
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
            a.add(a)  // cycle
            var err: NSError?
            let s = QsBridge.encode(a, options: nil, error: &err)
            #expect(s == nil)
            #expect(err != nil)
            #expect(err!.domain == EncodeErrorInfoObjC.domain)
            #expect(EncodeErrorObjC.kind(from: err!) == .cyclicObject)
        }

        // MARK: _bridgeUndefined — pure Swift containers

        @Test("bridgeUndefined recurses pure Swift [String: Any]")
        func bridgeUndefined_swiftDictionary_branch() throws {
            // Pure Swift container → exercises the zero-hit case `case let d as [String: Any]`
            let input: [String: Any] = [
                "n": 42,
                "d": ["y": "z"],  // nested dictionary to force recursion
            ]
            let o = EncodeOptionsObjC()
            o.encode = false  // keep output human-readable

            let s = try #require(QsBridge.encode(input, options: o, error: nil) as String?)
            // Order can differ; compare as a set.
            let parts = Set(s.split(separator: "&").map(String.init))
            #expect(parts == Set(["n=42", "d[y]=z"]))
        }

        @Test("bridgeUndefined recurses pure Swift [Any]")
        func bridgeUndefined_swiftArray_branch() throws {
            // Pure Swift array → exercises the zero-hit case `case let a as [Any]`
            let input: [Any] = ["lorem", 1234]
            let o = EncodeOptionsObjC()
            o.encode = false

            let s = try #require(QsBridge.encode(input, options: o, error: nil) as String?)
            #expect(s == "0=lorem&1=1234")
        }

        // MARK: bridgeInputForDecode — forceReduce path (casts succeed)

        @Test("bridgeInputForDecode(forceReduce:) takes reduce path")
        func decode_forceReduce_reduceBranch() {
            // Force the reduce(into:) path; with NSObject keys the (AnyHashable, Any) cast succeeds.
            final class WeirdKey: NSObject, NSCopying {
                func copy(with zone: NSZone? = nil) -> Any {
                    self
                }

                override var description: String {
                    "WeirdKey"
                }
            }

            let key = WeirdKey()
            let dict = NSMutableDictionary()
            dict[key] = "v"

            let bridged = QsBridge.bridgeInputForDecode(dict, forceReduce: true)
            let out = bridged as? [AnyHashable: Any]

            // The reduce branch ran (we don’t care about stringify fallback here);
            // lookup must use the original key wrapped in AnyHashable.
            #expect(out != nil && out?.count == 1)
            #expect(out?[AnyHashable(key)] as? String == "v")
        }

        // MARK: bridgeInputForDecode — NSArray branch (explicit)

        @Test("bridgeInputForDecode bridges NSArray → [Any]")
        func decode_nsarray_branch() {
            let a: NSArray = ["a", 1, NSNull()]
            let bridged = QsBridge.bridgeInputForDecode(a)
            let out = bridged as? [Any]
            #expect(out != nil && out?.count == 3)
            #expect(out?[0] as? String == "a")
            #expect(out?[1] as? Int == 1)
            #expect(out?[2] is NSNull)
        }

        // MARK: - Sentinel

        @Test("SentinelBridge: matchEncodedPart and forCharset return boxed enums")
        func sentinel_bridge_helpers() {
            let isoBox = SentinelBridge.matchEncodedPart(SentinelObjC.iso.encoded as NSString)
            let chsBox = SentinelBridge.matchEncodedPart(SentinelObjC.charset.encoded as NSString)
            #expect(isoBox?.intValue == SentinelObjC.iso.rawValue)
            #expect(chsBox?.intValue == SentinelObjC.charset.rawValue)

            let fromUtf8 = SentinelBridge.forCharset(String.Encoding.utf8.rawValue)
            let fromLatin1 = SentinelBridge.forCharset(String.Encoding.isoLatin1.rawValue)
            #expect(fromUtf8?.intValue == SentinelObjC.charset.rawValue)
            #expect(fromLatin1?.intValue == SentinelObjC.iso.rawValue)

            // description mirrors encoded
            #expect(SentinelObjC.iso.description == SentinelObjC.iso.encoded)
        }

        // MARK: - Error bridging

        @Test("EncodeErrorObjC: cyclic object maps to correct domain/code")
        func encode_error_mapping() {
            let m = NSMutableDictionary()
            m["self"] = m
            var err: NSError?
            let s = QsBridge.encode(m, options: nil, error: &err)
            #expect(s == nil)
            #expect(err != nil)
            #expect(err!.domain == EncodeErrorInfoObjC.domain)
            #expect(EncodeErrorObjC.kind(from: err!) == .cyclicObject)
        }

        @Test("DecodeErrorObjC: parameterLimitExceeded exposes userInfo limit")
        func decode_error_mapping() {
            let opts = DecodeOptionsObjC().with {
                $0.parameterLimit = 1
                $0.throwOnLimitExceeded = true
            }

            var err: NSError?
            let out = QsBridge.decode("a=b&c=d" as NSString, options: opts, error: &err)
            #expect(out == nil)
            #expect(err != nil)
            #expect(err!.domain == DecodeErrorInfoObjC.domain)
            #expect(err!.code == DecodeErrorCodeObjC.parameterLimitExceeded.rawValue)
            #expect((err!.userInfo[DecodeErrorInfoObjC.limitKey] as? Int) == 1)
        }

        // MARK: - ValueEncoder / DateSerializer

        @Test("valueEncoderBlock: unwraps optionals and encodes nil with strictNullHandling")
        func encoder_block_unwraps() {
            let o = EncodeOptionsObjC()
            o.strictNullHandling = true
            o.valueEncoderBlock = { value, _, _ in
                // Ensure Optional(123) arrives as 123, and nil arrives as empty
                if value == nil { return "" }
                return "\(value!)" as NSString
            }
            // top-level array → indices; value 123 should not be "Optional(123)"
            let s = QsBridge.encode(["a": 123 as NSNumber], options: o, error: nil)! as String
            #expect(s == "a=123")

            // strictNullHandling + nil
            let s2 = QsBridge.encode(["a": NSNull()], options: o, error: nil)! as String
            #expect(s2 == "a")  // key only
        }

        @Test("dateSerializerBlock: custom date formatting is applied")
        func dateSerializer_block() {
            let o = EncodeOptionsObjC()
            o.encode = false
            o.dateSerializerBlock = { (d: NSDate) in
                let ms = Int((d.timeIntervalSince1970 * 1000.0).rounded())
                return "\(ms)" as NSString
            }
            let s =
                QsBridge.encode(
                    ["t": Date(timeIntervalSince1970: 0.007)],
                    options: o, error: nil)! as String
            #expect(s == "t=7")
        }

        // MARK: - ValueDecoder

        @Test("valueDecoderBlock: can remap tokens before merge")
        func decoder_block() {
            let o = DecodeOptionsObjC()
            o.valueDecoderBlock = { (str: NSString?, _) in
                guard let s = str as String? else { return nil }
                switch s {
                case "%68%65%6c%6c%6f": return "hello"
                case "%61": return "a"
                default: return s
                }
            }
            let r = QsBridge.decode("%61=%68%65%6c%6c%6f" as NSString, options: o, error: nil)!
            #expect(r["a"] as? String == "hello")
        }

        // MARK: - Filters

        @Test("FunctionFilterObjC + UndefinedObjC drops keys")
        func filter_function_undefined() {
            let f = FunctionFilterObjC { key, value in
                (key as String) == "secret" ? UndefinedObjC() : value
            }
            let o = EncodeOptionsObjC()
            o.filter = .function(f)
            let s = QsBridge.encode(["a": "b", "secret": "x"], options: o, error: nil)! as String
            #expect(s == "a=b")
        }

        @Test("IterableFilterObjC selects keys/indices")
        func filter_iterable() {
            let o = EncodeOptionsObjC()
            o.encode = false
            o.filter = .iterable(IterableFilterObjC(keys: ["a", "c"]))
            let s =
                QsBridge.encode(["a": "1", "b": "2", "c": "3"], options: o, error: nil)! as String
            #expect(s == "a=1&c=3")
        }

        // MARK: - Sorting

        @Test("sortKeysCaseInsensitively orders keys A..Z ignoring case")
        func sort_caseInsensitive() {
            let o = EncodeOptionsObjC()
            o.encode = false
            o.sortKeysCaseInsensitively = true
            let s =
                QsBridge.encode(["b": "1", "A": "2", "a": "3"], options: o, error: nil)! as String
            #expect(s == "A=2&a=3&b=1")
        }

        @Test("sortComparatorBlock provides full control")
        func sort_customComparator() {
            let o = EncodeOptionsObjC()
            o.encode = false
            o.sortComparatorBlock = { a, b in
                let sa = String(describing: a ?? "")
                let sb = String(describing: b ?? "")
                return sa.compare(sb, options: .numeric).rawValue  // "2" < "10"
            }
            let s = QsBridge.encode(["10": "x", "2": "y"], options: o, error: nil)! as String
            #expect(s == "2=y&10=x")
        }

        // MARK: - Bridging helpers

        @Test("bridgeInputForEncode: NSDictionary non-string keys are stringified")
        func bridge_stringify_keys() {
            let dict: NSDictionary = [1: "one", 2: "two"]  // NSNumber keys
            let o = EncodeOptionsObjC()
            o.encode = false
            o.sortComparatorBlock = { a, b in
                let ia = Int(String(describing: a ?? "")) ?? 0
                let ib = Int(String(describing: b ?? "")) ?? 0
                return ia == ib ? 0 : (ia < ib ? -1 : 1)
            }
            let s = QsBridge.encode(dict, options: o, error: nil)! as String
            #expect(s == "1=one&2=two")
        }

        // MARK: - Async callbacks

        @Test("decodeAsyncOnMain calls back on main queue")
        func decodeAsyncOnMain_queue() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                QsBridge.decodeAsyncOnMain("a=b" as NSString, options: nil) { dict, _ in
                    #expect(dict?["a"] as? String == "b")
                    // Use pthread_main_np to avoid Thread.isMainThread async restriction
                    #expect(pthread_main_np() != 0)
                    cont.resume()
                }
            }
        }

        @Test("decodeAsync does NOT marshal to main")
        func decodeAsync_background() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                QsBridge.decodeAsync("a=b" as NSString, options: nil) { dict, _ in
                    #expect(dict?["a"] as? String == "b")
                    #expect(pthread_main_np() == 0)  // likely a background thread
                    cont.resume()
                }
            }
        }

        @Test("encodeAsyncOnMain / encodeAsync round-trip")
        func encodeAsync_callbacks() async {
            // On main
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                QsBridge.encodeAsyncOnMain(["a": "b"], options: nil) { s, _ in
                    #expect(s as String? == "a=b")
                    #expect(pthread_main_np() != 0)
                    cont.resume()
                }
            }
            // Background
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                QsBridge.encodeAsync(["a": "b"], options: nil) { s, _ in
                    #expect(s as String? == "a=b")
                    #expect(pthread_main_np() == 0)
                    cont.resume()
                }
            }
        }
    }
#endif

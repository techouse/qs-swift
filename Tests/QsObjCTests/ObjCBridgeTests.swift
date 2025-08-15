#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import OrderedCollections
    import Testing

    @testable import QsObjC

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

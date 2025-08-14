#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation

    // for pthread_main_np()
    #if canImport(Darwin)
        import Darwin
    #elseif canImport(Glibc)
        import Glibc
    #endif

    @testable import QsObjC
    @testable import QsSwift

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    @Suite("objc-bridge-extras")
    struct ObjCBridgeExtrasTests {

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
            var opts = DecodeOptionsObjC()
            opts.parameterLimit = 1
            opts.throwOnLimitExceeded = true

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

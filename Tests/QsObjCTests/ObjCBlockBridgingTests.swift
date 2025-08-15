#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    @testable import QsObjC

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    struct ObjCBlockBridgingTests {

        // Small helpers
        private func encode(
            _ dict: NSDictionary,
            configure: (EncodeOptionsObjC) -> Void
        ) -> String {
            let opts = EncodeOptionsObjC()
            configure(opts)
            var err: NSError?
            let s = QsBridge.encode(dict, options: opts, error: &err)
            #expect(err == nil, "encode error: \(String(describing: err))")
            return s as String? ?? ""
        }

        private func decode(
            _ qs: String,
            configure: (DecodeOptionsObjC) -> Void
        ) -> NSDictionary {
            let opts = DecodeOptionsObjC()
            configure(opts)
            var err: NSError?
            let out = QsBridge.decode(qs as NSString, options: opts, error: &err)
            #expect(err == nil, "decode error: \(String(describing: err))")
            return out ?? [:]
        }

        // MARK: - valueEncoderBlock

        @Test("objc-encode: custom valueEncoder block runs for keys and values")
        func objc_valueEncoder() throws {
            var seenFormat: NSNumber?

            let s = encode(["a": "hello"]) { o in
                o.valueEncoderBlock = { value, _, format in
                    seenFormat = format
                    // turn "a" -> "%61", "hello" -> "%68%65%6c%6c%6f"
                    let str: String
                    if let s = value as? String {
                        str = s
                    } else if let v = value {
                        str = String(describing: v)
                    } else {
                        str = ""
                    }
                    switch str {
                    case "a": return "%61"
                    case "hello": return "%68%65%6c%6c%6f"
                    default: return str as NSString
                    }
                }
                // leave defaults (encode=true, format=rfc3986)
            }

            #expect(s == "%61=%68%65%6c%6c%6f")
            #expect(seenFormat?.intValue == 0)  // .rfc3986

            // Flip to RFC 1738 and ensure the block sees format=1
            var seenFormat1738: NSNumber?
            _ = encode(["k": "v"]) { o in
                o.format = .rfc1738
                o.valueEncoderBlock = { _, _, format in
                    seenFormat1738 = format
                    return ""  // result not important for this assertion
                }
            }
            #expect(seenFormat1738?.intValue == 1)  // .rfc1738
        }

        // MARK: - dateSerializerBlock

        @Test("objc-encode: custom dateSerializer block is used")
        func objc_dateSerializer() throws {
            let date = Date(timeIntervalSince1970: 0.007)  // 7 ms
            let s = encode(["a": date]) { o in
                o.encode = false  // human-readable, mirrors core test style
                o.dateSerializerBlock = { (d: NSDate) in
                    let ms = Int((d.timeIntervalSince1970 * 1000.0).rounded())
                    return "\(ms)" as NSString
                }
            }
            #expect(s == "a=7")
        }

        // MARK: - valueDecoderBlock

        @Test("objc-decode: custom valueDecoder block maps tokens")
        func objc_valueDecoder() throws {
            var seenCharset: NSNumber?

            let r = decode("%61=%68%65%6c%6c%6f") { o in
                o.valueDecoderBlock = { token, charset in
                    seenCharset = charset
                    switch token as String? {
                    case "%61": return "a"
                    case "%68%65%6c%6c%6f": return "hello"
                    default: return token as String?
                    }
                }
            }

            #expect(r["a"] as? String == "hello")
            #expect(seenCharset?.uintValue == String.Encoding.utf8.rawValue)
        }
    }
#endif

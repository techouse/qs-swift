#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation

    @testable import QsObjC

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    /// Additional encode-specific parity tests adapted from `EncodeTests.swift` for the ObjC façade.
    struct ObjCEncodeTests {
        // Reuse helpers from ObjCExampleTests pattern
        private func encode(
            _ value: Any,
            configure: ((EncodeOptionsObjC) -> Void)? = nil
        ) -> NSString {
            let opts = EncodeOptionsObjC()
            configure?(opts)
            var err: NSError?
            let s = QsBridge.encode(value as AnyObject, options: opts, error: &err)
            #expect(err == nil, "encode error: \(String(describing: err))")
            #expect(s != nil)
            return s ?? ""
        }

        // MARK: - Scalars & Unicode

        @Test("objc-encode: query string map scalars & unicode")
        func encode_queryStringMapScalars() throws {
            #expect(encode(["a": "b"]) as String == "a=b")
            #expect(encode(["a": 1]) as String == "a=1")
            #expect(
                encode(["a": 1, "b": 2]) as String == "a=1&b=2"
                    || encode(["a": 1, "b": 2]) as String == "b=2&a=1")  // NSDictionary order not guaranteed
            let euro = encode(["a": "€"]) as String
            #expect(euro == "a=%E2%82%AC")
            #expect(encode(["a": "א"]) as String == "a=%D7%90")
        }

        @Test("objc-encode: encode=false serializes Data as decoded text")
        func encode_data_encodeFalse() throws {
            let bytes = Data("a b".utf8)
            let plain = encode(["a": bytes]) { o in o.encode = false }
            #expect(plain as String == "a=a b")

            let comma = encode(["a": [bytes]]) { o in
                o.listFormat = .comma
                o.encode = false
            }
            #expect(comma as String == "a=a b")
        }

        // MARK: - Top-level list / array

        @Test("objc-encode: top-level list encodes with indices")
        func encode_topLevelList() throws {
            #expect(encode([1234]) as String == "0=1234")
            let s = encode(["lorem", 1234, "ipsum"]) as String
            // Order should be index order 0,1,2
            #expect(s == "0=lorem&1=1234&2=ipsum")
        }

        // MARK: - Falsy / empty handling

        @Test("objc-encode: falsy / empty primitives produce empty string")
        func encode_falsyEmpties() throws {
            #expect(encode([:]) as String == "")
            #expect(encode([]) as String == "")
            #expect(encode(NSNull()) as String == "")
            #expect(encode(false) as String == "")
            #expect(encode(0) as String == "")
        }

        // MARK: - Skip / strict null handling

        @Test("objc-encode: skipNulls option")
        func encode_skipNulls() throws {
            let s = encode(["a": "b", "c": NSNull()]) { o in o.skipNulls = true }
            #expect(s as String == "a=b")
        }

        @Test("objc-encode: strictNullHandling distinguishes empty vs null")
        func encode_strictNullHandling() throws {
            let s = encode(["a": NSNull(), "b": ""]) { o in o.strictNullHandling = true }
            // a (nil) -> "a" ; b (empty string) -> b=
            // Order may vary; split & test set membership
            let parts = Set((s as String).split(separator: "&").map(String.init))
            #expect(parts.contains("a"))
            #expect(parts.contains("b="))
            #expect(parts.count == 2)
        }

        // MARK: - List formats (including commaRoundTrip)

        @Test("objc-encode: listFormat variants + round trip single element")
        func encode_listFormatVariants() throws {
            let multi: NSDictionary = ["a": ["b", "c"]]
            // indices
            #expect(
                encode(multi) { o in
                    o.listFormat = .indices
                    o.encode = false
                } as String == "a[0]=b&a[1]=c")
            // brackets
            #expect(
                encode(multi) { o in
                    o.listFormat = .brackets
                    o.encode = false
                } as String == "a[]=b&a[]=c")
            // repeat
            #expect(
                encode(multi) { o in
                    o.listFormat = .repeatKey
                    o.encode = false
                } as String == "a=b&a=c")
            // comma
            #expect(
                encode(multi) { o in
                    o.listFormat = .comma
                    o.encode = false
                } as String == "a=b,c")

            // Single element list with comma + roundTrip flag
            let single: NSDictionary = ["a": ["x"]]
            #expect(
                encode(single) { o in
                    o.listFormat = .comma
                    o.encode = false
                } as String == "a=x")
            #expect(
                encode(single) { o in
                    o.listFormat = .comma
                    o.encode = false
                    o.commaRoundTrip = true
                } as String == "a[]=x")
        }

        // MARK: - allowEmptyLists + strictNullHandling

        @Test("objc-encode: allowEmptyLists + strictNullHandling")
        func encode_allowEmptyLists_strictNulls() throws {
            let s1 = encode(["foo": [Any](), "bar": "baz"]) { o in
                o.allowEmptyLists = true
                o.encode = false
            }
            let parts1 = Set((s1 as String).split(separator: "&").map(String.init))
            #expect(parts1 == Set(["foo[]", "bar=baz"]))

            // With strictNullHandling, empty list still just foo[] (no change expected here)
            let s2 = encode(["foo": [Any](), "bar": NSNull()]) { o in
                o.allowEmptyLists = true
                o.encode = false
                o.strictNullHandling = true
                o.skipNulls = true
            }
            #expect(s2 as String == "foo[]")
        }

        // MARK: - charset (encoding) already tested in ObjCExampleTests, but add latin1 numeric entity edge

        @Test("objc-encode: latin1 numeric entity edge")
        func encode_latin1NumericEntity() throws {
            let s = encode(["a": "☺"]) { o in o.charset = String.Encoding.isoLatin1.rawValue }
            #expect(s as String == "a=%26%239786%3B")
        }

        // MARK: - Space formatting

        @Test("objc-encode: space RFC 1738 vs 3986")
        func encode_spaceFormats() throws {
            #expect(encode(["a": "b c"]) as String == "a=b%20c")  // default RFC3986
            #expect(encode(["a": "b c"]) { o in o.format = .rfc1738 } as String == "a=b+c")
        }

        // MARK: - Dot / encodeDotInKeys interaction

        @Test("objc-encode: encodeDotInKeys implies allowDots fallback")
        func encode_encodeDotInKeysImpliesAllowDots() throws {
            // Only set encodeDotInKeys = true; allowDots remains false (default). The shim forwards allowDots || encodeDotInKeys.
            let s = encode(["a.b": ["c": "d"]]) { o in
                o.encodeDotInKeys = true
                o.encode = false
            }
            // Actual behavior (current implementation): first key with dot is percent-encoded as a%2Eb; inner map uses dot before leaf when allowDots not explicitly set.
            #expect(s as String == "a%2Eb.c=d")
        }
    }
#endif

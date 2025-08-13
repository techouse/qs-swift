#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation

    @testable import QsObjC

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    struct ObjCExampleTests {
        // Shared constants used in charset tests (mirroring Swift ExampleTests)
        private let urlEncodedCheckmarkInUtf8 = "%E2%9C%93"
        private let urlEncodedOSlashInUtf8 = "%C3%B8"
        private let urlEncodedNumCheckmark = "%26%2310003%3B"
        private let urlEncodedNumSmiley = "%26%239786%3B"
        
        // Small helpers to keep the tests tidy
        private func decode(
            _ qs: String,
            configure: ((DecodeOptionsObjC) -> Void)? = nil
        ) -> NSDictionary {
            let opts = DecodeOptionsObjC()
            configure?(opts)
            var err: NSError?
            let out = QsBridge.decode(qs as NSString, options: opts, error: &err)
            #expect(err == nil, "decode error: \(String(describing: err))")
            #expect(out != nil)
            return out ?? [:]
        }

        private func encode(
            _ dict: NSDictionary,
            configure: ((EncodeOptionsObjC) -> Void)? = nil
        ) -> NSString {
            let opts = EncodeOptionsObjC()
            configure?(opts)
            var err: NSError?
            let s = QsBridge.encode(dict, options: opts, error: &err)
            #expect(err == nil, "encode error: \(String(describing: err))")
            #expect(s != nil)
            return s ?? ""
        }

        // MARK: - Simple

        @Test("simple: decodes a simple query string")
        func simple_decode() throws {
            let r = decode("a=c")
            #expect(r["a"] as? String == "c")
        }

        @Test("simple: encodes a simple map to a query string")
        func simple_encode() throws {
            let s = encode(["a": "c"])
            #expect(s as String == "a=c")
        }

        // MARK: - Decoding • Maps

        @Test("maps: nested with bracket notation")
        func maps_nested() throws {
            let r = decode("foo[bar]=baz")
            let foo = r["foo"] as? NSDictionary
            #expect(foo?["bar"] as? String == "baz")
        }

        @Test("maps: URI-encoded keys")
        func maps_uriEncodedKeys() throws {
            let r = decode("a%5Bb%5D=c")
            let a = r["a"] as? NSDictionary
            #expect(a?["b"] as? String == "c")
        }

        @Test("maps: deep nest")
        func maps_deepNest() throws {
            let r = decode("foo[bar][baz]=foobarbaz")
            let foo = r["foo"] as? NSDictionary
            let bar = foo?["bar"] as? NSDictionary
            #expect(bar?["baz"] as? String == "foobarbaz")
        }

        @Test("maps: default max depth trims remainder")
        func maps_defaultDepthTrims() throws {
            let r = decode("a[b][c][d][e][f][g][h][i]=j")
            let a = r["a"] as? NSDictionary
            let b = a?["b"] as? NSDictionary
            let c = b?["c"] as? NSDictionary
            let d = c?["d"] as? NSDictionary
            let e = d?["e"] as? NSDictionary
            let f = e?["f"] as? NSDictionary
            #expect(f?["[g][h][i]"] as? String == "j")
        }

        @Test("maps: override depth with DecodeOptions.depth")
        func maps_overrideDepth() throws {
            let r = decode("a[b][c][d][e][f][g][h][i]=j") { o in
                o.depth = 1
            }
            let a = r["a"] as? NSDictionary
            let b = a?["b"] as? NSDictionary
            #expect(b?["[c][d][e][f][g][h][i]"] as? String == "j")
        }

        @Test("maps: parameterLimit")
        func maps_parameterLimit() throws {
            let r = decode("a=b&c=d") { o in o.parameterLimit = 1 }
            #expect(r["a"] as? String == "b")
            #expect(r["c"] == nil)
        }

        @Test("maps: ignore query prefix")
        func maps_ignorePrefix() throws {
            let r = decode("?a=b&c=d") { o in o.ignoreQueryPrefix = true }
            #expect(r["a"] as? String == "b")
            #expect(r["c"] as? String == "d")
        }

        @Test("maps: custom delimiter")
        func maps_customDelimiter() throws {
            let r = decode("a=b;c=d") { o in o.delimiter = .semicolon }
            #expect(r["a"] as? String == "b")
            #expect(r["c"] as? String == "d")
        }

        @Test("maps: allowDots / decodeDotInKeys")
        func maps_allowDots() throws {
            let r1 = decode("a.b=c") { o in o.allowDots = true }
            let a = r1["a"] as? NSDictionary
            #expect(a?["b"] as? String == "c")

            let r2 = decode("name%252Eobj.first=John&name%252Eobj.last=Doe") { o in
                o.decodeDotInKeys = true
            }
            let nameObj = r2["name.obj"] as? NSDictionary
            #expect(nameObj?["first"] as? String == "John")
            #expect(nameObj?["last"] as? String == "Doe")
        }

        @Test("maps: allowEmptyLists")
        func maps_allowEmptyLists() throws {
            let r = decode("foo[]&bar=baz") { o in o.allowEmptyLists = true }
            #expect((r["foo"] as? [Any])?.isEmpty == true)
            #expect(r["bar"] as? String == "baz")
        }

        @Test("maps: duplicates default combine")
        func maps_duplicatesDefault() throws {
            let r = decode("foo=bar&foo=baz")
            let arr = r["foo"] as? [Any]
            #expect(arr?.count == 2)
            #expect(arr?.first as? String == "bar")
            #expect(arr?.last as? String == "baz")
        }

        @Test("maps: duplicates FIRST/LAST/COMBINE")
        func maps_duplicatesModes() throws {
            var r = decode("foo=bar&foo=baz") { o in o.duplicates = .combine }
            #expect((r["foo"] as? [Any])?.count == 2)

            r = decode("foo=bar&foo=baz") { o in o.duplicates = .first }
            #expect(r["foo"] as? String == "bar")

            r = decode("foo=bar&foo=baz") { o in o.duplicates = .last }
            #expect(r["foo"] as? String == "baz")
        }

        @Test("maps: latin1 charset for legacy browsers")
        func maps_latin1() throws {
            let r = decode("a=%A7") { o in o.charset = String.Encoding.isoLatin1.rawValue }
            #expect(r["a"] as? String == "§")
        }

        @Test("maps: charset sentinel with latin1")
        func maps_charsetSentinel_latin1() throws {
            let qs = "utf8=\(urlEncodedCheckmarkInUtf8)&a=\(urlEncodedOSlashInUtf8)"
            let r = decode(qs) { o in
                o.charset = String.Encoding.isoLatin1.rawValue
                o.charsetSentinel = true
            }
            #expect(r["a"] as? String == "ø")
        }

        @Test("maps: charset sentinel with utf8")
        func maps_charsetSentinel_utf8() throws {
            let qs = "utf8=\(urlEncodedNumCheckmark)&a=%F8"
            let r = decode(qs) { o in
                o.charset = String.Encoding.utf8.rawValue
                o.charsetSentinel = true
            }
            #expect(r["a"] as? String == "ø")
        }

        @Test("maps: interpret numeric entities")
        func maps_numericEntities() throws {
            let qs = "a=\(urlEncodedNumSmiley)"
            let r = decode(qs) { o in
                o.charset = String.Encoding.isoLatin1.rawValue
                o.interpretNumericEntities = true
            }
            #expect(r["a"] as? String == "☺")
        }

        // MARK: - Decoding • Lists

        @Test("lists: [] notation")
        func lists_brackets() throws {
            let r = decode("a[]=b&a[]=c")
            let a = r["a"] as? [Any]
            #expect(a?.count == 2)
            #expect(a?.first as? String == "b")
            #expect(a?.last as? String == "c")
        }

        @Test("lists: explicit indices")
        func lists_indices() throws {
            let r = decode("a[1]=c&a[0]=b")
            let a = r["a"] as? [Any]
            #expect(a?.count == 2)
            #expect(a?[0] as? String == "b")
            #expect(a?[1] as? String == "c")
        }

        @Test("lists: compact sparse preserving order")
        func lists_compactSparse() throws {
            let r = decode("a[1]=b&a[15]=c")
            let a = r["a"] as? [Any]
            #expect(a?.count == 2)
            #expect(a?.first as? String == "b")
            #expect(a?.last as? String == "c")
        }

        @Test("lists: preserve empty string values")
        func lists_preserveEmptyStrings() throws {
            var r = decode("a[]=&a[]=b")
            let a0 = r["a"] as? [String]
            #expect(a0 == ["", "b"])

            r = decode("a[0]=b&a[1]=&a[2]=c")
            let a1 = r["a"] as? [String]
            #expect(a1 == ["b", "", "c"])
        }

        @Test("lists: convert high indices to map keys")
        func lists_highIndexToMap() throws {
            let r = decode("a[100]=b")
            let a = r["a"] as? NSDictionary
            #expect(a?["100"] as? String == "b")
        }

        @Test("lists: override list limit (0)")
        func lists_overrideListLimit0() throws {
            let r = decode("a[1]=b") { o in o.listLimit = 0 }
            let a = r["a"] as? NSDictionary
            #expect(a?["1"] as? String == "b")
        }

        @Test("lists: disable list parsing entirely")
        func lists_disableParsing() throws {
            let r = decode("a[]=b") { o in o.parseLists = false }
            let a = r["a"] as? NSDictionary
            #expect(a?["0"] as? String == "b")
        }

        @Test("lists: merge mixed notations into map")
        func lists_mixedNotations() throws {
            let r = decode("a[0]=b&a[b]=c")
            let a = r["a"] as? NSDictionary
            #expect(a?["0"] as? String == "b")
            #expect(a?["b"] as? String == "c")
        }

        @Test("lists: lists of maps")
        func lists_ofMaps() throws {
            let r = decode("a[][b]=c")
            let a = r["a"] as? [Any]
            let first = a?.first as? NSDictionary
            #expect(first?["b"] as? String == "c")
        }

        @Test("lists: comma-separated values with comma option")
        func lists_commaOption() throws {
            let r = decode("a=b,c") { o in o.comma = true }
            #expect(r["a"] as? [String] == ["b", "c"])
        }

        // MARK: - Decoding • Primitive

        @Test("scalars: all values parsed as strings by default")
        func scalars_asStrings() throws {
            let r = decode("a=15&b=true&c=null")
            #expect(r["a"] as? String == "15")
            #expect(r["b"] as? String == "true")
            #expect(r["c"] as? String == "null")
        }

        // MARK: - Encoding

        @Test("encode: maps as expected")
        func encode_maps() throws {
            #expect(encode(["a": "b"]) as String == "a=b")
            #expect(encode(["a": ["b": "c"]]) as String == "a%5Bb%5D=c")
        }

        @Test("encode: encode=false leaves brackets")
        func encode_disableEncoding() throws {
            let s = encode(["a": ["b": "c"]]) { o in o.encode = false }
            #expect(s as String == "a[b]=c")
        }

        @Test("encode: encodeValuesOnly=true")
        func encode_valuesOnly() throws {
            let input: NSDictionary = [
                "a": "b",
                "c": ["d", "e=f"],
                "f": [["g"], ["h"]],
            ]
            let s = encode(input) { o in o.encodeValuesOnly = true }
            #expect(s as String == "a=b&c[0]=d&c[1]=e%3Df&f[0][0]=g&f[1][0]=h")
        }

        @Test("encode: lists with indices by default (encode=false)")
        func encode_listsDefault() throws {
            let s = encode(["a": ["b", "c", "d"]]) { o in o.encode = false }
            #expect(s as String == "a[0]=b&a[1]=c&a[2]=d")
        }

        @Test("encode: indices=false")
        func encode_indicesFalse() throws {
            let s = encode(["a": ["b", "c", "d"]]) { o in
                o.indices = false
                o.encode = false
            }
            #expect(s as String == "a=b&a=c&a=d")
        }

        @Test("encode: different list formats")
        func encode_listFormats() throws {
            var s = encode(["a": ["b", "c"]]) { o in
                o.listFormat = .indices
                o.encode = false
            }
            #expect(s as String == "a[0]=b&a[1]=c")

            s = encode(["a": ["b", "c"]]) { o in
                o.listFormat = .brackets
                o.encode = false
            }
            #expect(s as String == "a[]=b&a[]=c")

            s = encode(["a": ["b", "c"]]) { o in
                o.listFormat = .repeatKey
                o.encode = false
            }
            #expect(s as String == "a=b&a=c")

            s = encode(["a": ["b", "c"]]) { o in
                o.listFormat = .comma
                o.encode = false
            }
            #expect(s as String == "a=b,c")
        }

        @Test("encode: bracket notation for maps by default (encode=false)")
        func encode_bracketNotationForMaps() throws {
            let s = encode(["a": ["b": ["c": "d", "e": "f"]]]) { o in
                o.encode = false
                o.sortKeysCaseInsensitively = true  // to ensure ordered output of NSDictionary in tests
            }
            #expect(s as String == "a[b][c]=d&a[b][e]=f")
        }

        @Test("encode: dot notation with allowDots=true")
        func encode_allowDots() throws {
            let s = encode(["a": ["b": ["c": "d", "e": "f"]]]) { o in
                o.allowDots = true
                o.encode = false
                o.sortKeysCaseInsensitively = true  // to ensure ordered output of NSDictionary in tests
            }
            #expect(s as String == "a.b.c=d&a.b.e=f")
        }

        @Test("encode: encodeDotInKeys=true")
        func encode_encodeDotInKeys() throws {
            let s = encode(["name.obj": ["first": "John", "last": "Doe"]]) { o in
                o.allowDots = true
                o.encodeDotInKeys = true
            }
            #expect(s as String == "name%252Eobj.first=John&name%252Eobj.last=Doe")
        }

        @Test("encode: allowEmptyLists=true (encode=false)")
        func encode_allowEmptyLists() throws {
            let s = encode(["foo": [Any](), "bar": "baz"]) { o in
                o.allowEmptyLists = true
                o.encode = false
            }
            // order is not guaranteed → compare as a set of components
            let parts = Set((s as String).split(separator: "&").map(String.init))
            #expect(parts == Set(["foo[]", "bar=baz"]))
        }

        @Test("encode: empty strings and null values")
        func encode_emptyAndNull() throws {
            #expect(encode(["a": ""]) as String == "a=")
        }

        @Test("encode: empty collections → empty string")
        func encode_emptyCollections() throws {
            #expect(encode(["a": [Any]()]) as String == "")
            #expect(encode(["a": [String: Any]()]) as String == "")
            #expect(encode(["a": [[String: Any]]()]) as String == "")
            #expect(encode(["a": ["b": [Any]()]]) as String == "")
            #expect(encode(["a": ["b": [String: Any]()]]) as String == "")
        }

        @Test("encode: add query prefix")
        func encode_queryPrefix() throws {
            let s = encode(["a": "b", "c": "d"]) { o in o.addQueryPrefix = true }
            #expect(s as String == "?a=b&c=d")
        }

        @Test("encode: override delimiter")
        func encode_overrideDelimiter() throws {
            let s = encode(["a": "b", "c": "d"]) { o in o.delimiter = ";" }
            #expect(s as String == "a=b;c=d")
        }

        @Test("encode: serialize Date using default serializer (encode=false)")
        func encode_dateDefault() throws {
            let date = Date(timeIntervalSince1970: 0.007)  // 7 ms
            let s = encode(["a": date]) { o in o.encode = false }
            #expect(s as String == "a=1970-01-01T00:00:00.007Z")
        }

        @Test("encode: sort parameter keys (case-insensitive helper)")
        func encode_sortKeys() throws {
            let s = encode(["a": "c", "z": "y", "b": "f"]) { o in
                o.encode = false
                o.sortKeysCaseInsensitively = true
            }
            #expect(s as String == "a=c&b=f&z=y")
        }

        // MARK: - Null values

        @Test("nulls: treat null like empty string by default (encode)")
        func nulls_encodeDefaults() throws {
            let s = encode(["a": NSNull(), "b": ""]) { _ in }
            #expect(s as String == "a=&b=")
        }

        @Test("nulls: decoding treats 'a&b=' as empty strings")
        func nulls_decodeEmptyStrings() throws {
            let r = decode("a&b=")
            #expect(r["a"] as? String == "")
            #expect(r["b"] as? String == "")
        }

        @Test("nulls: strictNullHandling on encode")
        func nulls_encodeStrictNulls() throws {
            let s = encode(["a": NSNull(), "b": ""]) { o in o.strictNullHandling = true }
            #expect(s as String == "a&b=")
        }

        @Test("nulls: strictNullHandling on decode")
        func nulls_decodeStrictNulls() throws {
            let r = decode("a&b=") { o in o.strictNullHandling = true }
            #expect(r["a"] is NSNull)
            #expect(r["b"] as? String == "")
        }

        @Test("nulls: skipNulls on encode")
        func nulls_skipNulls() throws {
            let s = encode(["a": "b", "c": NSNull()]) { o in o.skipNulls = true }
            #expect(s as String == "a=b")
        }

        // MARK: - Charset (encoding)

        @Test("charset: encode using latin1")
        func charset_encodeLatin1() throws {
            let s = encode(["æ": "æ"]) { o in o.charset = String.Encoding.isoLatin1.rawValue }
            #expect(s as String == "%E6=%E6")
        }

        @Test("charset: characters not in latin1 → numeric entities")
        func charset_numericEntitiesWhenNeeded() throws {
            let s = encode(["a": "☺"]) { o in o.charset = String.Encoding.isoLatin1.rawValue }
            #expect(s as String == "a=%26%239786%3B")
        }

        @Test("charset: charsetSentinel with UTF-8")
        func charset_sentinelUtf8() throws {
            let s = encode(["a": "☺"]) { o in o.charsetSentinel = true }
            #expect(s as String == "utf8=%E2%9C%93&a=%E2%98%BA")
        }

        @Test("charset: charsetSentinel with latin1")
        func charset_sentinelLatin1() throws {
            let s = encode(["a": "æ"]) { o in
                o.charset = String.Encoding.isoLatin1.rawValue
                o.charsetSentinel = true
            }
            #expect(s as String == "utf8=%26%2310003%3B&a=%E6")
        }

        // MARK: - RFC 3986 vs RFC 1738 space encoding

        @Test("spaces: RFC 3986 default → %20")
        func spaces_default3986() throws {
            #expect(encode(["a": "b c"]) as String == "a=b%20c")
        }

        @Test("spaces: explicit RFC 3986")
        func spaces_explicit3986() throws {
            let s = encode(["a": "b c"]) { o in o.format = .rfc3986 }
            #expect(s as String == "a=b%20c")
        }

        @Test("spaces: RFC 1738 → +")
        func spaces_rfc1738() throws {
            let s = encode(["a": "b c"]) { o in o.format = .rfc1738 }
            #expect(s as String == "a=b+c")
        }
        
        // MARK: - Decoding • Maps (regex delimiter)

        @Test("maps: regex delimiter")
        func maps_regexDelimiter() throws {
            // Split on either ';' or ',' using a regex delimiter
            let r = decode("a=b;c=d") { o in
                // Use a plain character class to match ; or , (no whitespace tolerance)
                o.delimiter = DelimiterObjC(regexPattern: #"[;,]"#)!
            }
            #expect(r["a"] as? String == "b")
            #expect(r["c"] as? String == "d")
        }
        
        // MARK: - Encoding (omit Undefined)

        @Test("encode: omits undefined properties")
        func encode_omitsUndefined() throws {
            // NSNull encodes as empty value; Undefined should be omitted entirely
            let input: NSDictionary = [
                "a": NSNull(),
                "b": UndefinedObjC()
            ]
            let s = encode(input) { _ in }
            #expect(s as String == "a=")
        }
    }
#endif

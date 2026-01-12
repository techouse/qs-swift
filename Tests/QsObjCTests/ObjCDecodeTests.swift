// ObjCDecodeTests: subset of DecodeTests adapted for the Objective-C façade.
#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation

    @testable import QsObjC

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    struct ObjCDecodeTests {
        // Shared constants for charset-related tests
        private let urlEncodedCheckmarkInUtf8 = "%E2%9C%93"
        private let urlEncodedOSlashInUtf8 = "%C3%B8"
        private let urlEncodedNumCheckmark = "%26%2310003%3B"
        private let urlEncodedNumSmiley = "%26%239786%3B"

        // Helpers
        private func decode(_ qs: String, configure: ((DecodeOptionsObjC) -> Void)? = nil)
            -> NSDictionary
        {
            let opts = DecodeOptionsObjC()
            configure?(opts)
            var err: NSError?
            let out = QsBridge.decode(qs as NSString, options: opts, error: &err)
            #expect(err == nil, "decode error: \(String(describing: err))")
            #expect(out != nil)
            return out ?? [:]
        }

        private func decodeExpectingError(_ qs: String, configure: (DecodeOptionsObjC) -> Void)
            -> NSError?
        {
            let opts = DecodeOptionsObjC()
            configure(opts)
            var err: NSError?
            let out = QsBridge.decode(qs as NSString, options: opts, error: &err)
            #expect(out == nil)
            #expect(err != nil)
            return err
        }

        private func stringArray(_ any: Any?) -> [String]? {
            if let arr = any as? [String] { return arr }
            if let arr = any as? [Any] { return arr.compactMap { $0 as? String } }
            return nil
        }

        private func isNSNull(_ v: Any?) -> Bool { (v as AnyObject) is NSNull }

        // MARK: - Simple parsing

        @Test("objc-decode: parses simple string and plus→space")
        func simple_parse() throws {
            let r0 = decode("0=foo")
            #expect(r0["0"] as? String == "foo")

            let r1 = decode("foo=c++")
            #expect(r1["foo"] as? String == "c  ")
        }

        @Test("objc-decode: bracketed operator-style keys")
        func operatorKeys() throws {
            let r1 = decode("a[>=]=23")
            #expect((r1["a"] as? NSDictionary)?[">="] as? String == "23")
            let r2 = decode("a[<=>]==23")
            #expect((r2["a"] as? NSDictionary)?["<=>"] as? String == "=23")
            let r3 = decode("a[==]=23")
            #expect((r3["a"] as? NSDictionary)?["=="] as? String == "23")
        }

        // MARK: - strictNullHandling

        @Test("objc-decode: strictNullHandling distinguishes key with no =")
        func strictNullHandling_basic() throws {
            let r = decode("foo") { o in o.strictNullHandling = true }
            #expect(r["foo"] is NSNull)

            let r2 = decode("foo=bar&baz") { o in o.strictNullHandling = true }
            #expect(r2["foo"] as? String == "bar")
            #expect(r2["baz"] is NSNull)

            let r3 = decode("foo")
            let r4 = decode("foo=")
            #expect(r3["foo"] as? String == "")
            #expect(r4["foo"] as? String == "")
        }

        // MARK: - Multi-parameter

        @Test("objc-decode: multi-parameter example")
        func multiParameter() throws {
            let r = decode("cht=p3&chd=t:60,40&chs=250x100&chl=Hello|World")
            #expect(r["cht"] as? String == "p3")
            #expect(r["chd"] as? String == "t:60,40")
            #expect(r["chs"] as? String == "250x100")
            #expect(r["chl"] as? String == "Hello|World")
        }

        // MARK: - Comma option

        @Test("objc-decode: comma=false vs true")
        func commaOption() throws {
            let r1 = decode("a[]=b&a[]=c")
            #expect(stringArray(r1["a"]) == ["b", "c"])
            let r2 = decode("a=b,c")
            #expect(r2["a"] as? String == "b,c")

            let r3 = decode("a=b,c") { o in o.comma = true }
            #expect(stringArray(r3["a"]) == ["b", "c"])
        }

        @Test("objc-decode: comma listLimit throw")
        func commaLimitThrow() throws {
            let err = decodeExpectingError("a=b,c,d,e,f") { o in
                o.comma = true
                o.listLimit = 3
                o.throwOnLimitExceeded = true
            }
            #expect(err != nil)
        }

        // MARK: - Dot / decodeDotInKeys combinations (subset)

        @Test("objc-decode: dot key combinations subset")
        func dotKeyVariants() throws {
            // default (allowDots=false; decodeDotInKeys=false)
            let d0 = decode("name%252Eobj.first=John")
            #expect(d0["name%2Eobj.first"] as? String == "John")

            // allowDots = true
            let d1 = decode("a.b=c") { o in o.allowDots = true }
            let a1 = d1["a"] as? NSDictionary
            #expect(a1?["b"] as? String == "c")

            // decodeDotInKeys = true (which implies allowDots ORed in shim)
            let d2 = decode("name%252Eobj.first=John&name%252Eobj.last=Doe") { o in
                o.decodeDotInKeys = true
            }
            let nameObj = d2["name.obj"] as? NSDictionary
            #expect(nameObj?["first"] as? String == "John")
            #expect(nameObj?["last"] as? String == "Doe")
        }

        // MARK: - Empty lists

        @Test("objc-decode: allowEmptyLists vs default")
        func allowEmptyListsVariants() throws {
            let r1 = decode("foo[]&bar=baz") { o in o.allowEmptyLists = true }
            #expect(stringArray(r1["foo"])?.isEmpty == true)
            #expect(r1["bar"] as? String == "baz")

            let r2 = decode("foo[]&bar=baz") { o in o.allowEmptyLists = false }
            // Without allowEmptyLists we currently preserve an empty string element (matches shim behavior)
            #expect(stringArray(r2["foo"]) == [""])
        }

        @Test("objc-decode: allowEmptyLists + strictNullHandling")
        func allowEmptyListsStrictNulls() throws {
            let r = decode("testEmptyList[]") { o in
                o.allowEmptyLists = true
                o.strictNullHandling = true
            }
            #expect(stringArray(r["testEmptyList"])?.isEmpty == true)
        }

        // MARK: - Depth

        @Test("objc-decode: default depth trims remainder")
        func depthDefaultTrim() throws {
            let r = decode("a[b][c][d][e][f][g][h]=i")
            let a = r["a"] as? NSDictionary
            let b = a?["b"] as? NSDictionary
            let c = b?["c"] as? NSDictionary
            let d = c?["d"] as? NSDictionary
            let e = d?["e"] as? NSDictionary
            let f = e?["f"] as? NSDictionary
            #expect(f?["[g][h]"] as? String == "i")
        }

        @Test("objc-decode: depth=1 collapses deeper brackets")
        func depthOne() throws {
            let r = decode("a[b][c]=d") { o in o.depth = 1 }
            let a = r["a"] as? NSDictionary
            let b = a?["b"] as? NSDictionary
            #expect(b?["[c]"] as? String == "d")
        }

        // MARK: - Parameter & list limits

        @Test("objc-decode: parameterLimit truncates")
        func parameterLimitTruncates() throws {
            let r = decode("a=b&c=d") { o in o.parameterLimit = 1 }
            #expect(r["a"] as? String == "b")
            #expect(r["c"] == nil)
        }

        @Test("objc-decode: listLimit=0 forces map fallback")
        func listLimitZeroFallback() throws {
            let r = decode("a[1]=b") { o in o.listLimit = 0 }
            let a = r["a"] as? NSDictionary
            #expect(a?["1"] as? String == "b")
        }

        @Test("objc-decode: listLimit applies to [] notation")
        func listLimitZeroEmptyBrackets() throws {
            let r = decode("a[]=1&a[]=2") { o in o.listLimit = 0 }
            let a = r["a"] as? NSDictionary
            #expect(a?["0"] as? String == "1")
            #expect(a?["1"] as? String == "2")
        }

        @Test("objc-decode: parseLists=false forces map")
        func parseListsFalse() throws {
            let r = decode("a[]=b") { o in o.parseLists = false }
            let a = r["a"] as? NSDictionary
            #expect(a?["0"] as? String == "b")
        }

        // MARK: - List shapes

        @Test("objc-decode: list bracket and indices forms")
        func listForms() throws {
            let r1 = decode("a[]=b&a[]=c")
            #expect(stringArray(r1["a"]) == ["b", "c"])
            let r2 = decode("a[0]=b&a[1]=c")
            #expect(stringArray(r2["a"]) == ["b", "c"])
            let r3 = decode("a[100]=x")
            let a3 = r3["a"] as? NSDictionary
            #expect(a3?["100"] as? String == "x")
        }

        @Test("objc-decode: mixed list/map notation merges into map")
        func mixedNotations() throws {
            let r = decode("a[0]=b&a[b]=c")
            let a = r["a"] as? NSDictionary
            #expect(a?["0"] as? String == "b")
            #expect(a?["b"] as? String == "c")
        }

        @Test("objc-decode: list of maps")
        func listOfMaps() throws {
            let r = decode("a[][b]=c")
            let a = r["a"] as? [Any]
            let first = a?.first as? NSDictionary
            #expect(first?["b"] as? String == "c")
        }

        // MARK: - Duplicates policy

        @Test("objc-decode: duplicates first/last/combine")
        func duplicatesPolicies() throws {
            let combine = decode("foo=bar&foo=baz") { o in o.duplicates = .combine }
            #expect(stringArray(combine["foo"]) == ["bar", "baz"])

            let first = decode("foo=bar&foo=baz") { o in o.duplicates = .first }
            #expect(first["foo"] as? String == "bar")

            let last = decode("foo=bar&foo=baz") { o in o.duplicates = .last }
            #expect(last["foo"] as? String == "baz")
        }

        // MARK: - Charset decode

        @Test("objc-decode: latin1 charset")
        func charsetLatin1() throws {
            let r = decode("a=%A7") { o in o.charset = String.Encoding.isoLatin1.rawValue }
            #expect(r["a"] as? String == "§")
        }

        @Test("objc-decode: charset sentinel latin1→utf8 override")
        func charsetSentinelLatin1() throws {
            let qs = "utf8=\(urlEncodedCheckmarkInUtf8)&a=\(urlEncodedOSlashInUtf8)"
            let r = decode(qs) { o in
                o.charset = String.Encoding.isoLatin1.rawValue
                o.charsetSentinel = true
            }
            #expect(r["a"] as? String == "ø")
        }

        @Test("objc-decode: charset sentinel utf8")
        func charsetSentinelUtf8() throws {
            let qs = "utf8=\(urlEncodedNumCheckmark)&a=%F8"
            let r = decode(qs) { o in
                o.charset = String.Encoding.utf8.rawValue
                o.charsetSentinel = true
            }
            #expect(r["a"] as? String == "ø")
        }

        @Test("objc-decode: interpret numeric entities")
        func interpretNumericEntities() throws {
            let qs = "a=\(urlEncodedNumSmiley)"
            let r = decode(qs) { o in
                o.charset = String.Encoding.isoLatin1.rawValue
                o.interpretNumericEntities = true
            }
            #expect(r["a"] as? String == "☺")
        }
    }
#endif

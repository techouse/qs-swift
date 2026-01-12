import Foundation

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

#if canImport(XCTest)
    import XCTest
#endif

// Default: skip on CI (GitHub Actions sets CI=1), run locally
private let defaultSkip = ProcessInfo.processInfo.environment["CI"] != nil
private let skipExpensive = envFlag("SKIP_EXPENSIVE_TESTS") ?? defaultSkip
private let runExpensive = !skipExpensive

struct DecodeTests {
    @Test("decode - nested list handling in parseObject")
    func testDecode_NestedListHandling() async throws {
        // a) Round trip: a = [[ "nested" ]]
        let query1 = try Qs.encode(["a": [["nested"]]])
        let result1 = try Qs.decode(query1)
        #expect(as2DStrings(result1["a"] as Any?) == [["nested"]])

        // b) From string: a[0][0]=value  -> a = [[ "value" ]]
        let result2 = try Qs.decode("a[0][0]=value", options: DecodeOptions(depth: 5))
        #expect(as2DStrings(result2["a"] as Any?) == [["value"]])

        // c) a[0][]=first&a[0][]=second  -> a = [[ "first", "second" ]]
        let result3 = try Qs.decode("a[0][]=first&a[0][]=second")
        #expect(as2DStrings(result3["a"] as Any?) == [["first", "second"]])

        // d) a[0][2]=third  -> a = [[ "third" ]]
        let result4 = try Qs.decode("a[0][2]=third")
        #expect(as2DStrings(result4["a"] as Any?) == [["third"]])
    }

    @Test("Decoder.parseObject treats [] as dictionary key when lists are disabled")
    func parseObject_treatsEmptySegmentAsDictionaryKey() throws {
        let options = DecodeOptions(parseLists: false)
        let parsed = try Decoder.parseObject(
            chain: ["[]"],
            value: "value",
            options: options,
            valuesParsed: true
        )
        let dict = parsed as? [String: Any]
        #expect(dict?["0"] as? String == "value")
    }

    @Test("Decoder.parseObject normalizes optional arrays into NSNull placeholders")
    func parseObject_normalizesOptionalArrays() throws {
        let options = DecodeOptions(allowEmptyLists: true, strictNullHandling: true)
        let list: [Any?] = ["alpha", nil, Undefined.instance]
        let parsed = try Decoder.parseObject(
            chain: ["[]"],
            value: list,
            options: options,
            valuesParsed: true
        )
        let array = parsed as? [Any]
        #expect(array?.count == 3)
        #expect(array?[0] as? String == "alpha")

        let bridged = array as? NSArray
        #expect(bridged?[1] is NSNull)
        #expect(bridged?[2] is Undefined)
    }

    @Test("Decoder.parseObject maps optional array leaves to NSNull placeholders")
    func parseObject_optionalArrayLeafProducesNSNulls() throws {
        let options = DecodeOptions(allowEmptyLists: true)
        let list: [Any?] = ["first", nil, nil]
        let parsed = try Decoder.parseObject(
            chain: ["[]"],
            value: list,
            options: options,
            valuesParsed: true
        )

        let bridged = parsed as? NSArray
        #expect(bridged?.count == 3)
        #expect(bridged?[0] as? String == "first")
        #expect(bridged?[1] is NSNull)
        #expect(bridged?[2] is NSNull)
    }

    @Test("Decoder.parseObject reuses nested list length when appending []")
    func parseObject_reusesExistingListLength() throws {
        let nested: [Any?] = [[Any?](["existing", "values"])]
        let parsed = try Decoder.parseObject(
            chain: ["0", "[]"],
            value: nested,
            options: DecodeOptions(),
            valuesParsed: true
        )
        let dict = parsed as? [String: Any]
        let list = dict?["0"] as? [Any]
        #expect(list?.count == 1)
        let inner = list?.first as? [Any]
        #expect(inner?.count == 2)
        #expect(inner?.first as? String == "existing")
        #expect(inner?.last as? String == "values")
    }

    @Test("parseQueryStringValues - duplicates policy")
    func testDuplicatesPolicy() throws {
        // combine
        do {
            let opts = DecodeOptions(duplicates: .combine)
            let res = try Decoder.parseQueryStringValues("a=1&a=2", options: opts)
            #expect((res["a"] as? [Any?])?.compactMap { $0 as? String } == ["1", "2"])
        }

        // first
        do {
            let opts = DecodeOptions(duplicates: .first)
            let res = try Decoder.parseQueryStringValues("a=1&a=2", options: opts)
            #expect("\(res["a"]!)" == "1")
        }

        // last
        do {
            let opts = DecodeOptions(duplicates: .last)
            let res = try Decoder.parseQueryStringValues("a=1&a=2", options: opts)
            #expect("\(res["a"]!)" == "2")
        }
    }

    @Test("parseQueryStringValues applies custom decoder to comma lists")
    func parseQueryStringValues_customDecoderCommaLists() throws {
        let opts = DecodeOptions(
            decoder: { token, _, kind in
                guard kind == .value else { return token }
                return token?.uppercased()
            },
            comma: true
        )

        let result = try Decoder.parseQueryStringValues("tags=a,b", options: opts)
        let values = result["tags"] as? [Any]
        let strings = values?.compactMap { $0 as? String }
        #expect(strings == ["A", "B"])
    }

    @Test("decode - throws when input is not a String or Dictionary")
    func testDecode_Throws_WhenInputTypeInvalid() async throws {
        #expect(throws: Error.self) {
            _ = try Qs.decode(123)  // not String, not [String: Any]
        }
    }

    @Test("decode - parses a simple string")
    func testDecode_ParsesSimpleString() async throws {
        // "0=foo" → key "0"
        do {
            let r = try Qs.decode("0=foo")
            #expect((r["0"] as? String) == "foo")
        }

        // '+' decodes to space
        do {
            let r = try Qs.decode("foo=c++")
            #expect((r["foo"] as? String) == "c  ")
        }

        // bracketed keys with operators
        do {
            let r = try Qs.decode("a[>=]=23")
            let a = r["a"] as? [String: Any?]
            #expect((a?[">="] as? String) == "23")
        }
        do {
            let r = try Qs.decode("a[<=>]==23")
            let a = r["a"] as? [String: Any?]
            #expect((a?["<=>"] as? String) == "=23")
        }
        do {
            let r = try Qs.decode("a[==]=23")
            let a = r["a"] as? [String: Any?]
            #expect((a?["=="] as? String) == "23")
        }

        // strictNullHandling: key without '=' yields nil, else empty string
        do {
            let r = try Qs.decode("foo", options: DecodeOptions(strictNullHandling: true))
            #expect(r.keys.contains("foo"))
            #expect(isNSNull(r["foo"]))
        }

        do {
            let r1 = try Qs.decode("foo=bar&baz", options: DecodeOptions(strictNullHandling: true))
            #expect((r1["foo"] as? String) == "bar")
            #expect(r1.keys.contains("baz"))
            #expect(isNSNull(r1["baz"]))
        }

        do {
            let r2 = try Qs.decode("foo")
            let r3 = try Qs.decode("foo=")
            #expect((r2["foo"] as? String) == "")
            #expect((r3["foo"] as? String) == "")
        }

        // basic parsing
        do {
            let r = try Qs.decode("foo=bar")
            #expect((r["foo"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode(" foo = bar = baz ")
            #expect((r[" foo "] as? String) == " bar = baz ")
        }
        do {
            let r = try Qs.decode("foo=bar=baz")
            #expect((r["foo"] as? String) == "bar=baz")
        }
        do {
            let r = try Qs.decode("foo=bar&bar=baz")
            #expect((r["foo"] as? String) == "bar")
            #expect((r["bar"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode("foo2=bar2&baz2=")
            #expect((r["foo2"] as? String) == "bar2")
            #expect((r["baz2"] as? String) == "")
        }

        // multi-param example
        do {
            let r = try Qs.decode("cht=p3&chd=t:60,40&chs=250x100&chl=Hello|World")
            #expect((r["cht"] as? String) == "p3")
            #expect((r["chd"] as? String) == "t:60,40")
            #expect((r["chs"] as? String) == "250x100")
            #expect((r["chl"] as? String) == "Hello|World")
        }
    }

    @Test("comma: false")
    func testComma_False() async throws {
        do {
            let r = try Qs.decode("a[]=b&a[]=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[0]=b&a[1]=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a=b,c")
            #expect((r["a"] as? String) == "b,c")
        }
        do {
            let r = try Qs.decode("a=b&a=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
    }

    @Test("comma: true")
    func testComma_True() async throws {
        let opts = DecodeOptions(comma: true)

        do {
            let r = try Qs.decode("a[]=b&a[]=c", options: opts)
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[0]=b&a[1]=c", options: opts)
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a=b,c", options: opts)
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a=b&a=c", options: opts)
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
    }

    @Test("comma: true with list limit exceeded throws error")
    func testComma_ListLimit_Throws() async throws {
        let opts = DecodeOptions(listLimit: 3, comma: true, throwOnLimitExceeded: true)
        do {
            _ = try Qs.decode("a=b,c,d,e,f", options: opts)
            #expect(Bool(false))  // should not reach
        } catch {
            // Your error conforms to CustomStringConvertible; this checks the message.
            #expect(
                String(describing: error)
                    == "List limit exceeded. Only 3 elements allowed in a list.")
        }
    }

    @Test("allows enabling dot notation")
    func testAllowDots() async throws {
        do {
            let r = try Qs.decode("a.b=c")
            #expect((r["a.b"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a.b=c", options: DecodeOptions(allowDots: true))
            let a = r["a"] as? [String: Any]
            #expect((a?["b"] as? String) == "c")
        }
    }

    @Test("decode dot keys correctly")
    func testDecodeDotKeysVariants() async throws {
        // 1) allowDots=false, decodeDotInKeys=false
        do {
            let r = try Qs.decode(
                "name%252Eobj.first=John&name%252Eobj.last=Doe",
                options: DecodeOptions(allowDots: false, decodeDotInKeys: false)
            )
            #expect((r["name%2Eobj.first"] as? String) == "John")
            #expect((r["name%2Eobj.last"] as? String) == "Doe")
        }

        // 2) allowDots=true, decodeDotInKeys=false → dot splits only real dots
        do {
            let r = try Qs.decode(
                "name.obj.first=John&name.obj.last=Doe",
                options: DecodeOptions(allowDots: true, decodeDotInKeys: false)
            )
            let name = r["name"] as? [String: Any]
            let obj = name?["obj"] as? [String: Any]
            #expect((obj?["first"] as? String) == "John")
            #expect((obj?["last"] as? String) == "Doe")
        }

        // 3) allowDots=true, decodeDotInKeys=false with %2E literal kept
        do {
            let r = try Qs.decode(
                "name%252Eobj.first=John&name%252Eobj.last=Doe",
                options: DecodeOptions(allowDots: true, decodeDotInKeys: false)
            )
            let name = r["name%2Eobj"] as? [String: Any]
            #expect((name?["first"] as? String) == "John")
            #expect((name?["last"] as? String) == "Doe")
        }

        // 4) allowDots=true, decodeDotInKeys=true → %2E becomes '.' and dot splitting applies
        do {
            let r = try Qs.decode(
                "name%252Eobj.first=John&name%252Eobj.last=Doe",
                options: DecodeOptions(allowDots: true, decodeDotInKeys: true)
            )
            let name = r["name.obj"] as? [String: Any]
            #expect((name?["first"] as? String) == "John")
            #expect((name?["last"] as? String) == "Doe")
        }

        // 5) deep structure, allowDots=false, decodeDotInKeys=false
        do {
            let r = try Qs.decode(
                "name%252Eobj%252Esubobject.first%252Egodly%252Ename=John&name%252Eobj%252Esubobject.last=Doe",
                options: DecodeOptions(allowDots: false, decodeDotInKeys: false)
            )
            #expect((r["name%2Eobj%2Esubobject.first%2Egodly%2Ename"] as? String) == "John")
            #expect((r["name%2Eobj%2Esubobject.last"] as? String) == "Doe")
        }

        // 6) deep structure, allowDots=true, decodeDotInKeys=false
        do {
            let r = try Qs.decode(
                "name.obj.subobject.first.godly.name=John&name.obj.subobject.last=Doe",
                options: DecodeOptions(allowDots: true, decodeDotInKeys: false)
            )
            let name = r["name"] as? [String: Any]
            let obj = name?["obj"] as? [String: Any]
            let sub = obj?["subobject"] as? [String: Any]
            let first = sub?["first"] as? [String: Any]
            let godly = first?["godly"] as? [String: Any]
            #expect((godly?["name"] as? String) == "John")
            #expect((sub?["last"] as? String) == "Doe")
        }

        // 7) allowDots=true, decodeDotInKeys=true on %2E form
        do {
            let r = try Qs.decode(
                "name%252Eobj%252Esubobject.first%252Egodly%252Ename=John&name%252Eobj%252Esubobject.last=Doe",
                options: DecodeOptions(allowDots: true, decodeDotInKeys: true)
            )
            let sub = r["name.obj.subobject"] as? [String: Any]
            #expect((sub?["first.godly.name"] as? String) == "John")
            #expect((sub?["last"] as? String) == "Doe")
        }

        // 8) defaults (allowDots=false, decodeDotInKeys default false)
        do {
            let r1 = try Qs.decode("name%252Eobj.first=John&name%252Eobj.last=Doe")
            #expect((r1["name%2Eobj.first"] as? String) == "John")
            #expect((r1["name%2Eobj.last"] as? String) == "Doe")

            let r2 = try Qs.decode(
                "name%252Eobj.first=John&name%252Eobj.last=Doe",
                options: DecodeOptions(decodeDotInKeys: false)
            )
            #expect((r2["name%2Eobj.first"] as? String) == "John")
            #expect((r2["name%2Eobj.last"] as? String) == "Doe")

            let r3 = try Qs.decode(
                "name%252Eobj.first=John&name%252Eobj.last=Doe",
                options: DecodeOptions(decodeDotInKeys: true)
            )
            let obj = r3["name.obj"] as? [String: Any]
            #expect((obj?["first"] as? String) == "John")
            #expect((obj?["last"] as? String) == "Doe")
        }
    }

    @Test("decode dot keys with decodeDotInKeys=true and allowDots unset")
    func testDecodeDotKeys_DecodeDotsOnly() async throws {
        let r = try Qs.decode(
            "name%252Eobj%252Esubobject.first%252Egodly%252Ename=John&name%252Eobj%252Esubobject.last=Doe",
            options: DecodeOptions(decodeDotInKeys: true)
        )
        let sub = r["name.obj.subobject"] as? [String: Any]
        #expect((sub?["first.godly.name"] as? String) == "John")
        #expect((sub?["last"] as? String) == "Doe")
    }

    @Test("allows empty lists in obj values")
    func testAllowEmptyListsInObj() async throws {
        do {
            let r = try Qs.decode("foo[]&bar=baz", options: DecodeOptions(allowEmptyLists: true))
            #expect(asStrings(r["foo"]) == [])
            #expect((r["bar"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode("foo[]&bar=baz", options: DecodeOptions(allowEmptyLists: false))
            #expect(asStrings(r["foo"]) == [""])
            #expect((r["bar"] as? String) == "baz")
        }
    }

    @Test("allowEmptyLists + strictNullHandling")
    func testAllowEmptyLists_StrictNullHandling() async throws {
        // Requires Decoder.parseObject to treat NSNull like "empty" when allowEmptyLists is true.
        let r = try Qs.decode(
            "testEmptyList[]",
            options: DecodeOptions(allowEmptyLists: true, strictNullHandling: true)
        )
        #expect(asStrings(r["testEmptyList"]) == [])
    }

    @Test("parses a single nested string")
    func testSingleNested() async throws {
        let r = try Qs.decode("a[b]=c")
        let a = r["a"] as? [String: Any]
        #expect((a?["b"] as? String) == "c")
    }

    @Test("parses a double nested string")
    func testDoubleNested() async throws {
        let r = try Qs.decode("a[b][c]=d")
        let a = r["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        #expect((b?["c"] as? String) == "d")
    }

    @Test("defaults to a depth of 5")
    func testDefaultDepth5() async throws {
        let r = try Qs.decode("a[b][c][d][e][f][g][h]=i")
        let a = r["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        let c = b?["c"] as? [String: Any]
        let d = c?["d"] as? [String: Any]
        let e = d?["e"] as? [String: Any]
        let f = e?["f"] as? [String: Any]
        // at this point the remainder should be a single key "[g][h]"
        #expect((f?["[g][h]"] as? String) == "i")
    }

    @Test("only parses one level when depth = 1")
    func testDepthOne() async throws {
        do {
            let r = try Qs.decode("a[b][c]=d", options: DecodeOptions(depth: 1))
            let a = r["a"] as? [String: Any]
            let b = a?["b"] as? [String: Any]
            #expect((b?["[c]"] as? String) == "d")
        }
        do {
            let r = try Qs.decode("a[b][c][d]=e", options: DecodeOptions(depth: 1))
            let a = r["a"] as? [String: Any]
            let b = a?["b"] as? [String: Any]
            #expect((b?["[c][d]"] as? String) == "e")
        }
    }

    @Test("uses original key when depth = 0")
    func testDepthZero() async throws {
        do {
            let r = try Qs.decode("a[0]=b&a[1]=c", options: DecodeOptions(depth: 0))
            #expect((r["a[0]"] as? String) == "b")
            #expect((r["a[1]"] as? String) == "c")
        }
        do {
            let r = try Qs.decode(
                "a[0][0]=b&a[0][1]=c&a[1]=d&e=2", options: DecodeOptions(depth: 0))
            #expect((r["a[0][0]"] as? String) == "b")
            #expect((r["a[0][1]"] as? String) == "c")
            #expect((r["a[1]"] as? String) == "d")
            #expect((r["e"] as? String) == "2")
        }
    }

    @Test("parses a simple list")
    func testSimpleList() async throws {
        let r = try Qs.decode("a=b&a=c")
        #expect(asStrings(r["a"]) == ["b", "c"])
    }

    @Test("parses an explicit list")
    func testExplicitList() async throws {
        do {
            let r = try Qs.decode("a[]=b")
            #expect(asStrings(r["a"]) == ["b"])
        }
        do {
            let r = try Qs.decode("a[]=b&a[]=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[]=b&a[]=c&a[]=d")
            #expect(asStrings(r["a"]) == ["b", "c", "d"])
        }
    }

    @Test("parses a mix of simple and explicit lists")
    func testMixedLists() async throws {
        do {
            let r = try Qs.decode("a=b&a[]=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[]=b&a=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[0]=b&a=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a=b&a[0]=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }

        do {
            let r = try Qs.decode("a[1]=b&a=c", options: DecodeOptions(listLimit: 20))
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[]=b&a=c", options: DecodeOptions(listLimit: 0))
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[]=b&a=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }

        do {
            let r = try Qs.decode("a=b&a[1]=c", options: DecodeOptions(listLimit: 20))
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a=b&a[]=c", options: DecodeOptions(listLimit: 0))
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a=b&a[]=c")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
    }

    @Test("parses a nested list")
    func testNestedList() async throws {
        do {
            let r = try Qs.decode("a[b][]=c&a[b][]=d")
            let a = r["a"] as? [String: Any]
            #expect(asStrings(a?["b"]) == ["c", "d"])
        }
        do {
            let r = try Qs.decode("a[>=]=25")
            let a = r["a"] as? [String: Any]
            #expect((a?[">="] as? String) == "25")
        }
    }

    @Test("decodes nested lists with parentKey not null")
    func testNestedListWithIndexParent() async throws {
        let r = try Qs.decode("a[0][]=b")
        #expect(as2DStrings(r["a"]) == [["b"]])
    }

    @Test("decode - allows to specify list indices")
    func testDecode_ListIndices() async throws {
        do {
            let r = try Qs.decode("a[1]=c&a[0]=b&a[2]=d")
            #expect(asStrings(r["a"]) == ["b", "c", "d"])
        }
        do {
            let r = try Qs.decode("a[1]=c&a[0]=b")
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[1]=c", options: DecodeOptions(listLimit: 20))
            #expect(asStrings(r["a"]) == ["c"])
        }
        do {
            // listLimit = 0 → only index 0 can arrayify; index 1 stays a map key
            let r = try Qs.decode("a[1]=c", options: DecodeOptions(listLimit: 0))
            let a = asDictString(r["a"])
            #expect((a?["1"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[1]=c")
            #expect(asStrings(r["a"]) == ["c"])
        }
        do {
            // parseLists = false → keep indices as *string* keys
            let r = try Qs.decode("a[0]=b&a[2]=c", options: DecodeOptions(parseLists: false))
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["2"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[0]=b&a[2]=c", options: DecodeOptions(parseLists: true))
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
        do {
            let r = try Qs.decode("a[1]=b&a[15]=c", options: DecodeOptions(parseLists: false))
            let a = asDictString(r["a"])
            #expect((a?["1"] as? String) == "b")
            #expect((a?["15"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[1]=b&a[15]=c", options: DecodeOptions(parseLists: true))
            #expect(asStrings(r["a"]) == ["b", "c"])
        }
    }

    @Test("decode - limits specific list indices to listLimit")
    func testDecode_ListIndexLimit() async throws {
        do {
            let r = try Qs.decode("a[20]=a", options: DecodeOptions(listLimit: 20))
            #expect(asStrings(r["a"]) == ["a"])
        }
        do {
            let r = try Qs.decode("a[21]=a", options: DecodeOptions(listLimit: 20))
            let a = asDictString(r["a"])
            #expect((a?["21"] as? String) == "a")
        }
        do {
            let r = try Qs.decode("a[20]=a")
            #expect(asStrings(r["a"]) == ["a"])
        }
        do {
            let r = try Qs.decode("a[21]=a")
            let a = asDictString(r["a"])
            #expect((a?["21"] as? String) == "a")
        }
    }

    @Test("decode - supports keys that begin with a number")
    func testDecode_KeyBeginsWithNumber() async throws {
        let r = try Qs.decode("a[12b]=c")
        let a = r["a"] as? [String: Any]
        #expect((a?["12b"] as? String) == "c")
    }

    @Test("decode - supports encoded equals signs")
    func testDecode_EncodedEquals() async throws {
        let r = try Qs.decode("he%3Dllo=th%3Dere")
        #expect((r["he=llo"] as? String) == "th=ere")
    }

    @Test("decode - is ok with url encoded strings")
    func testDecode_URLEncodedSegments() async throws {
        do {
            let r = try Qs.decode("a[b%20c]=d")
            let a = r["a"] as? [String: Any]
            #expect((a?["b c"] as? String) == "d")
        }
        do {
            let r = try Qs.decode("a[b]=c%20d")
            let a = r["a"] as? [String: Any]
            #expect((a?["b"] as? String) == "c d")
        }
    }

    @Test("decode - allows brackets in the value")
    func testDecode_BracketsInValue() async throws {
        do {
            let r = try Qs.decode(#"pets=["tobi"]"#)
            #expect((r["pets"] as? String) == #"["tobi"]"#)
        }
        do {
            let r = try Qs.decode(#"operators=[">=", "<="]"#)
            #expect((r["operators"] as? String) == #"[">=", "<="]"#)
        }
    }

    @Test("decode - allows empty values")
    func testDecode_EmptyInput() async throws {
        #expect((try Qs.decode("")).isEmpty)
        #expect((try Qs.decode(nil as Any?)).isEmpty)
    }

    @Test("decode - transforms lists to maps")
    func testDecode_ListsToMaps() async throws {
        do {
            let r = try Qs.decode("foo[0]=bar&foo[bad]=baz")
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode("foo[bad]=baz&foo[0]=bar")
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo[bad]=baz&foo[]=bar")
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo[]=bar&foo[bad]=baz")
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode("foo[bad]=baz&foo[]=bar&foo[]=foo")
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["1"] as? String) == "foo")
        }
        do {
            let r = try Qs.decode("foo[0][a]=a&foo[0][b]=b&foo[1][a]=aa&foo[1][b]=bb")
            let foo = r["foo"] as? [Any]
            let m0 = foo?[0] as? [String: Any]
            let m1 = foo?[1] as? [String: Any]
            #expect((m0?["a"] as? String) == "a")
            #expect((m0?["b"] as? String) == "b")
            #expect((m1?["a"] as? String) == "aa")
            #expect((m1?["b"] as? String) == "bb")
        }
    }

    @Test("decode - transforms lists to maps (dot notation)")
    func testDecode_ListsToMaps_DotNotation() async throws {
        do {
            let r = try Qs.decode(
                "foo[0].baz=bar&fool.bad=baz", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let zero = foo?.first as? [String: Any]
            #expect((zero?["baz"] as? String) == "bar")
            let fool = r["fool"] as? [String: Any]
            #expect((fool?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo[0].baz=bar&fool.bad.boo=baz", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let zero = foo?.first as? [String: Any]
            #expect((zero?["baz"] as? String) == "bar")
            let fool = r["fool"] as? [String: Any]
            let bad = fool?["bad"] as? [String: Any]
            #expect((bad?["boo"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo[0][0].baz=bar&fool.bad=baz", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let level1 = foo?.first as? [Any]
            let level2 = level1?.first as? [String: Any]
            #expect((level2?["baz"] as? String) == "bar")
            let fool = r["fool"] as? [String: Any]
            #expect((fool?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo[0].baz[0]=15&foo[0].bar=2", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let zero = foo?.first as? [String: Any]
            #expect(asStrings(zero?["baz"]) == ["15"])
            #expect((zero?["bar"] as? String) == "2")
        }
        do {
            let r = try Qs.decode(
                "foo[0].baz[0]=15&foo[0].baz[1]=16&foo[0].bar=2",
                options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let zero = foo?.first as? [String: Any]
            #expect(asStrings(zero?["baz"]) == ["15", "16"])
            #expect((zero?["bar"] as? String) == "2")
        }
        do {
            let r = try Qs.decode("foo.bad=baz&foo[0]=bar", options: DecodeOptions(allowDots: true))
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo.bad=baz&foo[]=bar", options: DecodeOptions(allowDots: true))
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo[]=bar&foo.bad=baz", options: DecodeOptions(allowDots: true))
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo.bad=baz&foo[]=bar&foo[]=foo", options: DecodeOptions(allowDots: true))
            let foo = asDictAnyHashable(r["foo"])
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["1"] as? String) == "foo")
        }
        do {
            let r = try Qs.decode(
                "foo[0].a=a&foo[0].b=b&foo[1].a=aa&foo[1].b=bb",
                options: DecodeOptions(allowDots: true)
            )
            let foo = r["foo"] as? [Any]
            let m0 = foo?[0] as? [String: Any]
            let m1 = foo?[1] as? [String: Any]
            #expect((m0?["a"] as? String) == "a")
            #expect((m0?["b"] as? String) == "b")
            #expect((m1?["a"] as? String) == "aa")
            #expect((m1?["b"] as? String) == "bb")
        }
    }

    @Test("decode - correctly prunes undefined values when converting a list to a map")
    func testDecode_PruneUndefinedOnListToMap() async throws {
        let r = try Qs.decode("a[2]=b&a[99999999]=c")
        let a = asDictAnyHashable(r["a"])
        #expect((a?["2"] as? String) == "b")
        #expect((a?["99999999"] as? String) == "c")
    }

    @Test("decode - supports malformed uri characters")
    func testDecode_MalformedURI() async throws {
        do {
            let r = try Qs.decode("{%:%}", options: DecodeOptions(strictNullHandling: true))
            #expect(r.keys.contains("{%:%}"))
            #expect(isNSNullValue(r["{%:%}"]))
        }
        do {
            let r = try Qs.decode("{%:%}=")
            #expect((r["{%:%}"] as? String) == "")
        }
        do {
            let r = try Qs.decode("foo=%:%}")
            #expect((r["foo"] as? String) == "%:%}")
        }
    }

    @Test("decode - does not produce empty keys")
    func testDecode_NoEmptyKeys() async throws {
        let r = try Qs.decode("_r=1&")
        #expect((r["_r"] as? String) == "1")
    }

    @Test("decode - parses lists of maps")
    func testDecode_ListOfMaps() async throws {
        do {
            let r = try Qs.decode("a[][b]=c")
            let a = r["a"] as? [Any]
            let m0 = a?.first as? [String: Any]
            #expect((m0?["b"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[0][b]=c")
            let a = r["a"] as? [Any]
            let m0 = a?.first as? [String: Any]
            #expect((m0?["b"] as? String) == "c")
        }
    }

    @Test("DecodeOptions convenience decoders bridge legacy closures")
    func decodeOptions_convenienceLegacy() {
        let legacy: LegacyDecoder = { value, charset in
            let label = charset == .utf8 ? "utf8" : "other"
            return "\(label):\(value ?? "nil")"
        }

        let options = DecodeOptions(legacyDecoder: legacy)
        let decoded = options.getDecoder("value", charset: String.Encoding.utf8) as? String
        #expect(decoded == "utf8:value")

        let fallback = options.decodeValue("other", charset: String.Encoding.isoLatin1) as? String
        #expect(fallback == "other:other")
    }

    @Test("decode - allows for empty strings in lists")
    func testDecode_EmptyStringsInLists() async throws {
        do {
            let r = try Qs.decode("a[]=b&a[]=&a[]=c")
            #expect(asStrings(r["a"]) == ["b", "", "c"])
        }
        do {
            let r = try Qs.decode(
                "a[0]=b&a[1]&a[2]=c&a[19]=",
                options: DecodeOptions(listLimit: 20, strictNullHandling: true)
            )
            let arr = r["a"] as? [Any]
            #expect((arr?[0] as? String) == "b")
            #expect(isNSNullValue(arr?[1]))
            #expect((arr?[2] as? String) == "c")
            #expect((arr?[3] as? String) == "")
        }
        do {
            let r = try Qs.decode(
                "a[]=b&a[]&a[]=c&a[]=",
                options: DecodeOptions(listLimit: 0, strictNullHandling: true)
            )
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect(isNSNullValue(a?["1"]))
            #expect((a?["2"] as? String) == "c")
            #expect((a?["3"] as? String) == "")
        }
        do {
            let r = try Qs.decode(
                "a[0]=b&a[1]=&a[2]=c&a[19]",
                options: DecodeOptions(listLimit: 20, strictNullHandling: true)
            )
            let arr = r["a"] as? [Any]
            #expect((arr?[0] as? String) == "b")
            #expect((arr?[1] as? String) == "")
            #expect((arr?[2] as? String) == "c")
            #expect(isNSNullValue(arr?[3]))
        }
        do {
            let r = try Qs.decode(
                "a[]=b&a[]=&a[]=c&a[]",
                options: DecodeOptions(listLimit: 0, strictNullHandling: true)
            )
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "")
            #expect((a?["2"] as? String) == "c")
            #expect(isNSNullValue(a?["3"]))
        }
        do {
            let r = try Qs.decode("a[]=&a[]=b&a[]=c")
            #expect(asStrings(r["a"]) == ["", "b", "c"])
        }
    }

    @Test("decode - compacts sparse lists")
    func testDecode_CompactsSparseLists() async throws {
        // a[10]=1&a[2]=2  -> ["2","1"]
        do {
            let r = try Qs.decode("a[10]=1&a[2]=2", options: DecodeOptions(listLimit: 20))
            #expect(asStrings(r["a"]) == ["2", "1"])
        }

        // a[1][b][2][c]=1 -> ["a": [ { "b": [ { "c": "1" } ] } ]]
        do {
            let r = try Qs.decode("a[1][b][2][c]=1", options: DecodeOptions(listLimit: 20))
            let a = r["a"] as? [Any]
            let level1 = a?.first as? [String: Any]
            let bArr = level1?["b"] as? [Any]
            let firstMap = bArr?.first as? [String: Any]
            #expect((firstMap?["c"] as? String) == "1")
        }

        // a[1][2][3][c]=1 -> ["a": [[[ { "c": "1" } ]]]]
        do {
            let r = try Qs.decode("a[1][2][3][c]=1", options: DecodeOptions(listLimit: 20))
            let a = r["a"] as? [Any]
            let l1 = a?.first as? [Any]
            let l2 = l1?.first as? [Any]
            let l3 = l2?.first as? [String: Any]
            #expect((l3?["c"] as? String) == "1")
        }

        // a[1][2][3][c][1]=1 -> ["a": [[[ { "c": ["1"] } ]]]]
        do {
            let r = try Qs.decode("a[1][2][3][c][1]=1", options: DecodeOptions(listLimit: 20))
            let a = r["a"] as? [Any]
            let l1 = a?.first as? [Any]
            let l2 = l1?.first as? [Any]
            let l3 = l2?.first as? [String: Any]
            #expect(asStrings(l3?["c"]) == ["1"])
        }
    }

    @Test("decode - parses semi-parsed strings")
    func testDecode_SemiParsed() async throws {
        do {
            let r = try Qs.decode("a[b]=c")
            let a = r["a"] as? [String: Any]
            #expect((a?["b"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[b]=c&a[d]=e")
            let a = r["a"] as? [String: Any]
            #expect((a?["b"] as? String) == "c")
            #expect((a?["d"] as? String) == "e")
        }
    }

    @Test("decode - parses buffers correctly")
    func testDecode_Buffers() async throws {
        let b = "test".data(using: .utf8)!
        let r = try Qs.decode(["a": b])
        #expect((r["a"] as? Data) == b)
    }

    @Test("decode - parses jquery-param strings")
    func testDecode_jQueryParam() async throws {
        let encoded =
            "filter%5B0%5D%5B%5D=int1&filter%5B0%5D%5B%5D=%3D&filter%5B0%5D%5B%5D=77&filter%5B%5D=and&filter%5B2%5D%5B%5D=int2&filter%5B2%5D%5B%5D=%3D&filter%5B2%5D%5B%5D=8"
        let r = try Qs.decode(encoded)
        let filter = r["filter"] as? [Any]
        #expect((filter?[0] as? [String]) == ["int1", "=", "77"])
        #expect((filter?[1] as? String) == "and")
        #expect((filter?[2] as? [String]) == ["int2", "=", "8"])
    }

    @Test("decode - continues parsing when no parent is found")
    func testDecode_NoParent() async throws {
        do {
            let r = try Qs.decode("[]=&a=b")
            #expect((r["0"] as? String) == "")  // "0" as a string key
            #expect((r["a"] as? String) == "b")
        }
        do {
            let r = try Qs.decode("[]&a=b", options: DecodeOptions(strictNullHandling: true))
            #expect(isNSNullValue(r["0"]))  // still "0" as a string key
            #expect((r["a"] as? String) == "b")
        }
        do {
            let r = try Qs.decode("[foo]=bar")
            #expect((r["foo"] as? String) == "bar")
        }
    }

    @Test("decode - does not error when parsing a very long list")
    func testDecode_LongList() async throws {
        var s = "a[]=a"
        // Roughly double the string repeatedly to exceed 128KB of bytes
        while s.utf8.count < 128 * 1024 {
            s.append("&")
            s.append(s)
        }
        // Should not throw
        _ = try Qs.decode(s)
    }

    // MARK: - Delimiters

    @Test("decode - parses with alternative string delimiter")
    func testDecode_AltStringDelimiter() async throws {
        let r = try Qs.decode("a=b;c=d", options: DecodeOptions(delimiter: StringDelimiter(";")))
        #expect((r["a"] as? String) == "b")
        #expect((r["c"] as? String) == "d")
    }

    @Test("decode - parses with alternative regex delimiter")
    func testDecode_AltRegexDelimiter() async throws {
        let r = try Qs.decode(
            "a=b; c=d", options: DecodeOptions(delimiter: RegexDelimiter("[;,] *")))
        #expect((r["a"] as? String) == "b")
        #expect((r["c"] as? String) == "d")
    }

    // MARK: - Parameter limit

    @Test("decode - parameter limit override")
    func testDecode_ParameterLimitOverride() async throws {
        let r = try Qs.decode("a=b&c=d", options: DecodeOptions(parameterLimit: 1))
        #expect(r.count == 1)
        #expect((r["a"] as? String) == "b")
    }

    @Test("decode - parameter limit Int.max")
    func testDecode_ParameterLimitMax() async throws {
        let r = try Qs.decode("a=b&c=d", options: DecodeOptions(parameterLimit: .max))
        #expect((r["a"] as? String) == "b")
        #expect((r["c"] as? String) == "d")
    }

    // MARK: - List limit + disabling list parsing
    // NOTE: numeric “map” keys are strings in Swift ("0","1",...)

    @Test("decode - list limit overrides")
    func testDecode_ListLimitOverrides() async throws {
        do {
            let r = try Qs.decode("a[0]=b", options: DecodeOptions(listLimit: -1))
            let a = r["a"] as? [String: Any]
            #expect((a?["0"] as? String) == "b")
        }
        do {
            let r = try Qs.decode("a[0]=b", options: DecodeOptions(listLimit: 0))
            #expect(asStrings(r["a"]) == ["b"])
        }
        do {
            let r = try Qs.decode("a[-1]=b", options: DecodeOptions(listLimit: -1))
            let a = r["a"] as? [String: Any]
            #expect((a?["-1"] as? String) == "b")
        }
        do {
            let r = try Qs.decode("a[-1]=b", options: DecodeOptions(listLimit: 0))
            let a = r["a"] as? [String: Any]
            #expect((a?["-1"] as? String) == "b")
        }
        do {
            let r = try Qs.decode("a[0]=b&a[1]=c", options: DecodeOptions(listLimit: -1))
            let a = r["a"] as? [String: Any]
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[0]=b&a[1]=c", options: DecodeOptions(listLimit: 0))
            let a = r["a"] as? [String: Any]
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "c")
        }
    }

    @Test("decode - disable list parsing")
    func testDecode_DisableListParsing() async throws {
        let r1 = try Qs.decode("a[0]=b&a[1]=c", options: DecodeOptions(parseLists: false))
        let a1 = r1["a"] as? [String: Any]
        #expect((a1?["0"] as? String) == "b")
        #expect((a1?["1"] as? String) == "c")

        let r2 = try Qs.decode("a[]=b", options: DecodeOptions(parseLists: false))
        let a2 = r2["a"] as? [String: Any]
        #expect((a2?["0"] as? String) == "b")
    }

    // MARK: - Ignore query prefix

    @Test("decode - allows for query string prefix")
    func testDecode_IgnoreQueryPrefix() async throws {
        do {
            let r = try Qs.decode("?foo=bar", options: DecodeOptions(ignoreQueryPrefix: true))
            #expect((r["foo"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo=bar", options: DecodeOptions(ignoreQueryPrefix: true))
            #expect((r["foo"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("?foo=bar", options: DecodeOptions(ignoreQueryPrefix: false))
            #expect((r["?foo"] as? String) == "bar")
        }
    }

    // MARK: - Map input

    @Test("decode - parses a map input")
    func testDecode_ParsesMapInput() async throws {
        let input: [String: Any?] = [
            "user[name]": ["pop[bob]": 3],
            "user[email]": nil,
        ]
        let r = try Qs.decode(input)
        let user = r["user"] as? [String: Any]
        let name = user?["name"] as? [String: Any]
        #expect((name?["pop[bob]"] as? Int) == 3)
        #expect(isNSNullValue(user?["email"]))
    }

    @Test("decode - AnyHashable key collisions are deterministic (String wins)")
    func testDecode_AnyHashableKeyCollision_StringWins() throws {
        // Different literal orders, same outcome.
        do {
            let input1: [AnyHashable: Any] = [1: "int-one", "1": "string-one"]
            let r1 = try Qs.decode(input1)
            #expect(r1["1"] as? String == "string-one")
        }
        do {
            let input2: [AnyHashable: Any] = ["1": "string-one", 1: "int-one"]
            let r2 = try Qs.decode(input2)
            #expect(r2["1"] as? String == "string-one")
        }
    }

    // MARK: - Comma parsing

    @Test("decode - comma=true basic cases")
    func testDecode_CommaParsing() async throws {
        do {
            let r = try Qs.decode("foo=bar,tee", options: DecodeOptions(comma: true))
            #expect(asStrings(r["foo"]) == ["bar", "tee"])
        }
        do {
            let r = try Qs.decode("foo[bar]=coffee,tee", options: DecodeOptions(comma: true))
            let foo = r["foo"] as? [String: Any]
            #expect(asStrings(foo?["bar"]) == ["coffee", "tee"])
        }
        do {
            let r = try Qs.decode("foo=", options: DecodeOptions(comma: true))
            #expect((r["foo"] as? String) == "")
        }
        do {
            let r1 = try Qs.decode("foo", options: DecodeOptions(comma: true))
            #expect((r1["foo"] as? String) == "")
            let r2 = try Qs.decode(
                "foo", options: DecodeOptions(comma: true, strictNullHandling: true))
            #expect(isNSNullValue(r2["foo"]))
        }
        do {
            #expect(asStrings(try Qs.decode("a[0]=c")["a"]) == ["c"])
            #expect(asStrings(try Qs.decode("a[]=c")["a"]) == ["c"])
            #expect(
                asStrings(try Qs.decode("a[]=c", options: DecodeOptions(comma: true))["a"]) == ["c"]
            )
        }
        do {
            #expect(asStrings(try Qs.decode("a[0]=c&a[1]=d")["a"]) == ["c", "d"])
            #expect(asStrings(try Qs.decode("a[]=c&a[]=d")["a"]) == ["c", "d"])
            #expect(
                asStrings(try Qs.decode("a=c,d", options: DecodeOptions(comma: true))["a"]) == [
                    "c", "d",
                ])
        }
    }

    @Test("decode - comma in map values")
    func testDecode_CommaInMapValues() async throws {
        let input = ["foo": "bar,tee"]
        let r1 = try Qs.decode(input, options: DecodeOptions(comma: false))
        #expect((r1["foo"] as? String) == "bar,tee")

        let r2 = try Qs.decode(input, options: DecodeOptions(comma: true))
        #expect(asStrings(r2["foo"]) == ["bar", "tee"])
    }

    @Test("decode - custom number decoder with comma=true")
    func testDecode_NumberDecoder_Comma() async throws {
        let numberDecoder: ScalarDecoder = { s, _, _ in
            if let s, let n = Int(s) { return n }
            return Utils.decode(s, charset: .utf8)
        }
        let r1 = try Qs.decode("foo=1", options: DecodeOptions(decoder: numberDecoder, comma: true))
        #expect((r1["foo"] as? Int) == 1)
        let r0 = try Qs.decode("foo=0", options: DecodeOptions(decoder: numberDecoder, comma: true))
        #expect((r0["foo"] as? Int) == 0)
    }

    @Test("decode - brackets hold lists of lists with comma=true")
    func testDecode_Comma_ListOfLists() async throws {
        do {
            let r = try Qs.decode("foo[]=1,2,3&foo[]=4,5,6", options: DecodeOptions(comma: true))
            #expect(as2DStrings(r["foo"]) == [["1", "2", "3"], ["4", "5", "6"]])
        }
        do {
            let r = try Qs.decode("foo[]=1,2,3&foo[]=", options: DecodeOptions(comma: true))
            // second element is the empty string
            let foo = r["foo"] as? [Any]
            #expect(asStrings(foo?.first) == ["1", "2", "3"])
            #expect((foo?.dropFirst().first as? String) == "")
        }
        do {
            let r = try Qs.decode("foo[]=1,2,3&foo[]=,", options: DecodeOptions(comma: true))
            #expect(as2DStrings(r["foo"]) == [["1", "2", "3"], ["", ""]])
        }
        do {
            let r = try Qs.decode("foo[]=1,2,3&foo[]=a", options: DecodeOptions(comma: true))
            let foo = r["foo"] as? [Any]
            #expect(asStrings(foo?.first) == ["1", "2", "3"])
            #expect((foo?.dropFirst().first as? String) == "a")
        }
    }

    @Test("decode - percent-encoded commas treated as text with comma=true")
    func testDecode_CommaPercentEncoded() async throws {
        do {
            let r = try Qs.decode("foo=a%2Cb", options: DecodeOptions(comma: true))
            #expect((r["foo"] as? String) == "a,b")
        }
        do {
            let r = try Qs.decode("foo=a%2C%20b,d", options: DecodeOptions(comma: true))
            #expect(asStrings(r["foo"]) == ["a, b", "d"])
        }
        do {
            let r = try Qs.decode("foo=a%2C%20b,c%2C%20d", options: DecodeOptions(comma: true))
            #expect(asStrings(r["foo"]) == ["a, b", "c, d"])
        }
    }

    // MARK: - Dot-notation on map inputs

    @Test("decode - parses a map in dot notation")
    func testDecode_MapDotNotation() async throws {
        let input: [String: Any?] = [
            "user.name": ["pop[bob]": 3],
            "user.email.": nil,
        ]
        let r = try Qs.decode(input, options: DecodeOptions(allowDots: true))
        let user = r["user"] as? [String: Any]
        let name = user?["name"] as? [String: Any]
        #expect((name?["pop[bob]"] as? Int) == 3)
        #expect(isNSNullValue(user?["email"]))
    }

    @Test("decode - parses a map and not child values")
    func testDecode_MapNotChildValues() async throws {
        let input: [String: Any?] = [
            "user[name]": ["pop[bob]": ["test": 3]],
            "user[email]": nil,
        ]
        let r = try Qs.decode(input)
        let user = r["user"] as? [String: Any]
        let name = user?["name"] as? [String: Any]
        let pop = name?["pop[bob]"] as? [String: Any]
        #expect((pop?["test"] as? Int) == 3)
        #expect(isNSNullValue(user?["email"]))
    }

    // MARK: - jQuery-style param strings

    @Test("decode - parses jquery-param strings")
    func testDecode_jQueryParam1() async throws {
        let encoded =
            "filter%5B0%5D%5B%5D=int1&filter%5B0%5D%5B%5D=%3D&filter%5B0%5D%5B%5D=77&filter%5B%5D=and&filter%5B2%5D%5B%5D=int2&filter%5B2%5D%5B%5D=%3D&filter%5B2%5D%5B%5D=8"
        let r = try Qs.decode(encoded)
        let filter = r["filter"] as? [Any]
        #expect(asStrings(filter?.first) == ["int1", "=", "77"])
        #expect((filter?.dropFirst().first as? String) == "and")
        #expect(asStrings(filter?.dropFirst(2).first) == ["int2", "=", "8"])
    }

    // MARK: - Misc edge cases

    @Test("decode - does not produce empty keys")
    func testDecode_NoEmptyKeys1() async throws {
        let r = try Qs.decode("_r=1&")
        #expect(r.keys.sorted() == ["_r"])
        #expect((r["_r"] as? String) == "1")
    }

    @Test("decode - parses lists of maps")
    func testDecode_ListsOfMaps() async throws {
        do {
            let r = try Qs.decode("a[][b]=c")
            let a = r["a"] as? [Any]
            let first = a?.first as? [String: Any]
            #expect((first?["b"] as? String) == "c")
        }
        do {
            let r = try Qs.decode("a[0][b]=c")
            let a = r["a"] as? [Any]
            let first = a?.first as? [String: Any]
            #expect((first?["b"] as? String) == "c")
        }
    }

    @Test("decode - allows empty strings in lists (strictNullHandling variants)")
    func testDecode_EmptyStringsInLists1() async throws {
        #expect(asStrings(try Qs.decode("a[]=b&a[]=&a[]=c")["a"]) == ["b", "", "c"])

        do {
            let r = try Qs.decode(
                "a[0]=b&a[1]&a[2]=c&a[19]=",
                options: DecodeOptions(listLimit: 20, strictNullHandling: true))
            // after compaction, ["b", null, "c", ""]
            let a = r["a"] as? [Any]
            #expect((a?[0] as? String) == "b")
            #expect(isNSNullValue(a?[1]))
            #expect((a?[2] as? String) == "c")
            #expect((a?[3] as? String) == "")
        }
        do {
            let r = try Qs.decode(
                "a[]=b&a[]&a[]=c&a[]=",
                options: DecodeOptions(listLimit: 0, strictNullHandling: true))
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect(isNSNullValue(a?["1"]))
            #expect((a?["2"] as? String) == "c")
            #expect((a?["3"] as? String) == "")
        }
        do {
            let r = try Qs.decode(
                "a[0]=b&a[1]=&a[2]=c&a[19]",
                options: DecodeOptions(listLimit: 20, strictNullHandling: true))
            let a = r["a"] as? [Any]
            #expect((a?[0] as? String) == "b")
            #expect((a?[1] as? String) == "")
            #expect((a?[2] as? String) == "c")
            #expect(isNSNullValue(a?[3]))
        }
        do {
            let r = try Qs.decode(
                "a[]=b&a[]=&a[]=c&a[]",
                options: DecodeOptions(listLimit: 0, strictNullHandling: true))
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "")
            #expect((a?["2"] as? String) == "c")
            #expect(isNSNullValue(a?["3"]))
        }
        #expect(asStrings(try Qs.decode("a[]=&a[]=b&a[]=c")["a"]) == ["", "b", "c"])
    }

    // MARK: - Simple nesting + brackets

    @Test("decode - simple/double nested strings")
    func testDecode_Nesting() async throws {
        #expect(((try Qs.decode("a[b]=c")["a"] as? [String: Any])?["b"] as? String) == "c")
        let r2 = try Qs.decode("a[b][c]=d")
        let a2 = r2["a"] as? [String: Any]
        let b2 = a2?["b"] as? [String: Any]
        #expect((b2?["c"] as? String) == "d")
    }

    // MARK: - Transforms lists to maps (mixed keys)

    @Test("decode - transforms lists to maps when mixed")
    func testDecode_TransformsListsToMaps() async throws {
        do {
            let r = try Qs.decode("foo[0]=bar&foo[bad]=baz")
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode("foo[bad]=baz&foo[0]=bar")
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo[bad]=baz&foo[]=bar")
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo[]=bar&foo[bad]=baz")
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode("foo[bad]=baz&foo[]=bar&foo[]=foo")
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["1"] as? String) == "foo")
        }
        do {
            let r = try Qs.decode("foo[0][a]=a&foo[0][b]=b&foo[1][a]=aa&foo[1][b]=bb")
            let foo = r["foo"] as? [Any]
            let m0 = foo?.first as? [String: Any]
            let m1 = foo?.dropFirst().first as? [String: Any]
            #expect((m0?["a"] as? String) == "a")
            #expect((m0?["b"] as? String) == "b")
            #expect((m1?["a"] as? String) == "aa")
            #expect((m1?["b"] as? String) == "bb")
        }
    }

    // MARK: - Dot notation + lists to maps

    @Test("decode - transforms lists to maps (dot notation)")
    func testDecode_TransformsListsToMaps_Dot() async throws {
        do {
            let r = try Qs.decode(
                "foo[0].baz=bar&fool.bad=baz", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let first = foo?.first as? [String: Any]
            #expect((first?["baz"] as? String) == "bar")
            let fool = r["fool"] as? [String: Any]
            #expect((fool?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo[0].baz=bar&fool.bad.boo=baz",
                options: DecodeOptions(allowDots: true))
            let fool = r["fool"] as? [String: Any]
            let bad = fool?["bad"] as? [String: Any]
            #expect((bad?["boo"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo[0][0].baz=bar&fool.bad=baz",
                options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let l0 = foo?.first as? [Any]
            let first = l0?.first as? [String: Any]
            #expect((first?["baz"] as? String) == "bar")
            let fool = r["fool"] as? [String: Any]
            #expect((fool?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo[0].baz[0]=15&foo[0].bar=2",
                options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let first = foo?.first as? [String: Any]
            #expect(asStrings(first?["baz"]) == ["15"])
            #expect((first?["bar"] as? String) == "2")
        }
        do {
            let r = try Qs.decode(
                "foo[0].baz[0]=15&foo[0].baz[1]=16&foo[0].bar=2",
                options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let first = foo?.first as? [String: Any]
            #expect(asStrings(first?["baz"]) == ["15", "16"])
            #expect((first?["bar"] as? String) == "2")
        }
        do {
            let r = try Qs.decode("foo.bad=baz&foo[0]=bar", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo.bad=baz&foo[]=bar", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
        }
        do {
            let r = try Qs.decode("foo[]=bar&foo.bad=baz", options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["bad"] as? String) == "baz")
        }
        do {
            let r = try Qs.decode(
                "foo.bad=baz&foo[]=bar&foo[]=foo",
                options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [String: Any]
            #expect((foo?["bad"] as? String) == "baz")
            #expect((foo?["0"] as? String) == "bar")
            #expect((foo?["1"] as? String) == "foo")
        }
        do {
            let r = try Qs.decode(
                "foo[0].a=a&foo[0].b=b&foo[1].a=aa&foo[1].b=bb",
                options: DecodeOptions(allowDots: true))
            let foo = r["foo"] as? [Any]
            let m0 = foo?.first as? [String: Any]
            let m1 = foo?.dropFirst().first as? [String: Any]
            #expect((m0?["a"] as? String) == "a")
            #expect((m0?["b"] as? String) == "b")
            #expect((m1?["a"] as? String) == "aa")
            #expect((m1?["b"] as? String) == "bb")
        }
    }

    // MARK: - Prune undefined when converting list→map

    @Test("decode - prunes undefined when converting list→map")
    func testDecode_PrunesUndefined() async throws {
        let r = try Qs.decode("a[2]=b&a[99999999]=c")
        let a = r["a"] as? [String: Any]
        #expect((a?["2"] as? String) == "b")
        #expect((a?["99999999"] as? String) == "c")
    }

    // MARK: - Malformed URI characters

    @Test("decode - supports malformed URI chars")
    func testDecode_MalformedURI1() async throws {
        do {
            let r = try Qs.decode("{%:%}", options: DecodeOptions(strictNullHandling: true))
            #expect(r.keys.contains("{%:%}"))
            #expect(isNSNullValue(r["{%:%}"]))
        }
        do {
            let r = try Qs.decode("{%:%}=")
            #expect((r["{%:%}"] as? String) == "")
        }
        do {
            let r = try Qs.decode("foo=%:%}")
            #expect((r["foo"] as? String) == "%:%}")
        }
    }

    // MARK: - Bracket edge keys

    @Test("decode - params starting with closing bracket")
    func testDecode_StartingWithClosingBracket() async throws {
        #expect((try Qs.decode("]=toString")["]"] as? String) == "toString")
        #expect((try Qs.decode("]]=toString")["]]"] as? String) == "toString")
        #expect((try Qs.decode("]hello]=toString")["]hello]"] as? String) == "toString")
    }

    @Test("decode - params starting with starting bracket")
    func testDecode_StartingWithStartingBracket() async throws {
        #expect((try Qs.decode("[=toString")["["] as? String) == "toString")
        #expect((try Qs.decode("[[=toString")["[["] as? String) == "toString")
        #expect((try Qs.decode("[hello[=toString")["[hello["] as? String) == "toString")
    }

    // MARK: - Misc small ones

    @Test("decode - add keys to maps")
    func testDecode_AddKeysToMaps() async throws {
        let r = try Qs.decode("a[b]=c")
        let a = r["a"] as? [String: Any]
        #expect((a?["b"] as? String) == "c")
    }

    @Test("decode - can return null maps and mixed indexes")
    func testDecode_CanReturnNullMaps() async throws {
        // a[b]=c & a[hasOwnProperty]=d
        do {
            let r = try Qs.decode("a[b]=c&a[hasOwnProperty]=d")
            let a = r["a"] as? [String: Any]
            #expect((a?["b"] as? String) == "c")
            #expect((a?["hasOwnProperty"] as? String) == "d")
        }

        // nil input → empty
        #expect(try Qs.decode(nil as Any?).isEmpty)

        // a[]=b & a[c]=d → map with "0" and "c"
        do {
            let r = try Qs.decode("a[]=b&a[c]=d")
            let a = r["a"] as? [String: Any]
            #expect((a?["0"] as? String) == "b")
            #expect((a?["c"] as? String) == "d")
        }
    }
}

// MARK: - Custom decoder / charset

@Suite("custom decoder")
struct CustomDecoderTests {
    @Test("decode - custom decoder (toy kanji example)")
    func testDecode_CustomDecoder() async throws {
        let custom: ScalarDecoder = { s, _, _ in
            s?
                .replacingOccurrences(of: "%8c%a7", with: "県")
                .replacingOccurrences(of: "%91%e5%8d%e3%95%7b", with: "大阪府")
        }
        let r = try Qs.decode("%8c%a7=%91%e5%8d%e3%95%7b", options: DecodeOptions(decoder: custom))
        #expect((r["県"] as? String) == "大阪府")
    }

    @Test("decode - ISO-8859-1 charset")
    func testDecode_ISO8859_1() async throws {
        let r = try Qs.decode("%A2=%BD", options: DecodeOptions(charset: .isoLatin1))
        #expect((r["¢"] as? String) == "½")
    }
}

// MARK: - “Does not crash” style checks

@Suite("does not crash")
struct DoesNotCrashTests {
    @Test("decode - does not crash on circular references")
    func testDecode_Circular_NoCrash() async throws {
        var a: [String: Any?] = [:]
        a["b"] = a  // self-reference

        let r = try Qs.decode(["foo[bar]": "baz", "foo[baz]": a])
        let foo = r["foo"] as? [String: Any]
        #expect(foo != nil)
        #expect((foo?.keys.contains("bar") ?? false))
        #expect((foo?.keys.contains("baz") ?? false))
        #expect((foo?["bar"] as? String) == "baz")
        // Just assert it’s there; identity-equality on recursive structures isn’t trivial to check here.
        #expect(foo?["baz"] != nil)
    }

    /// NOTE: This test uses a very conservative depth limit to avoid stack overflows.
    ///       It is not intended to test the maximum depth of bridging. The test below
    ///       `testDecode_DeepMaps_NoTimeout_Main` is designed for that purpose.
    @Test("decode - deep maps do not time out")
    func testDecode_DeepMaps_NoTimeout_Safe() async throws {
        let depth = 2500  // conservative to avoid ARC’s recursive deinit on worker threads
        var s = "foo"
        for _ in 0..<depth { s += "[p]" }
        s += "=bar"

        let r = try Qs.decode(s, options: DecodeOptions(depth: depth))
        #expect(r.keys.contains("foo"))

        var actual = 0
        var ref: Any? = r["foo"]
        while let dict = ref as? [String: Any], let next = dict["p"] {
            ref = next
            actual += 1
        }
        #expect(actual == depth)
    }

    #if DEBUG && os(macOS)
        @MainActor
        @Test(
            "decode – deep maps (very deep, MainActor)",
            .enabled(if: runExpensive, "expensive: set SKIP_EXPENSIVE_TESTS=0 to run; 1 to skip")
        )
        func testDecode_DeepMaps_VeryDeep_Main() async throws {
            let depth = 5000
            var s = "foo"
            for _ in 0..<depth { s += "[p]" }
            s += "=bar"
            let r = try Qs.decode(s, options: DecodeOptions(depth: depth))
            #expect(r.keys.contains("foo"))
            var actual = 0
            var ref: Any? = r["foo"]
            while let dict = ref as? [String: Any], let next = dict["p"] {
                ref = next
                actual += 1
            }
            #expect(actual == depth)
        }
    #endif
}

@inline(__always)
private func skipOnCI(_ reason: String) throws {
    if ProcessInfo.processInfo.environment["CI"] != nil {
        throw XCTSkip(reason)
    }
}

// MARK: - Data / Date / Regex passthrough

@Suite("data date regex passthrough")
struct DataDateRegexTests {
    @Test("decode - parses Data correctly")
    func testDecode_Data() async throws {
        let data = Data("test".utf8)
        let r = try Qs.decode(["a": data])
        #expect((r["a"] as? Data) == data)
    }

    @Test("decode - parses Date correctly")
    func testDecode_Date() async throws {
        let now = Date()
        let r = try Qs.decode(["a": now])
        #expect((r["a"] as? Date) == now)
    }

    @Test("decode - parses regular expressions correctly")
    func testDecode_Regex() async throws {
        let re = try NSRegularExpression(pattern: "^test$")
        let r = try Qs.decode(["a": re])
        let out = r["a"] as? NSRegularExpression
        #expect(out?.pattern == "^test$")
    }

    @Test("async decode off-main")
    func testDecodeAsync_Background() async throws {
        let m = try await Qs.decodeAsync("a[b][c]=1&x=2").value
        #expect((m["a"] as? [String: Any])?["b"] != nil)
    }

    @MainActor
    @Test("async decode returns on main")
    func testDecodeAsync_MainActor() async throws {
        let m = try await Qs.decodeAsyncOnMain("k=v").value

        #if os(Linux)
            // On Linux, the MainActor is not guaranteed to be backed by the OS main thread.
            // Record as a known issue instead of branching expectations.
            try withKnownIssue("Linux: MainActor is not guaranteed to be the OS main thread") {
                let isMain = Thread.isMainThread  // we're already on MainActor
                #expect(isMain)
            }
        #else
            let isMain = await MainActor.run { Thread.isMainThread }
            #expect(isMain)
        #endif

        #expect(m["k"] as? String == "v")
    }

    @Test("decodeAsync returns on MainActor")
    func testDecodeAsync_OnMain() async throws {
        let wrapped = try await Qs.decodeAsyncOnMain("k=v")  // OK: DecodedMap is Sendable
        let m = wrapped.value
        #expect(m["k"] as? String == "v")
    }

    @Test("decodeAsyncValue runs off-main")
    func testDecodeAsyncValue() async throws {
        let s = "a[b]=1"
        let result = try await Qs.decodeAsyncValue(s)
        // Not asserting thread here—just ensuring it works and returns a value.
        #expect((result["a"] as? [String: Any])?["b"] != nil)
    }
}

// MARK: - DecodeOptions parity with Kotlin (DecodeOptionsSpec.kt)
@Suite("DecodeOptions (Kotlin parity)")
struct DecodeOptionsParityTests {
    private let charsets: [String.Encoding] = [.utf8, .isoLatin1]

    @Test("KEY maps %2E/%2e inside brackets to '.' when allowDots=true (UTF-8/ISO-8859-1)")
    func keyProtectsEncodedDotsInsideBrackets_allowDotsTrue() throws {
        for cs in charsets {
            let opts = DecodeOptions(allowDots: true)
            #expect((opts.decode("a[%2E]", cs, .key) as? String) == "a[.]")
            #expect((opts.decode("a[%2e]", cs, .key) as? String) == "a[.]")
        }
    }

    @Test(
        "KEY maps %2E outside brackets to '.' when allowDots=true; independent of decodeDotInKeys")
    func keyMapsEncodedDotOutsideBrackets_allowDotsTrue() throws {
        for cs in charsets {
            let opts1 = DecodeOptions(allowDots: true, decodeDotInKeys: false)
            let opts2 = DecodeOptions(allowDots: true, decodeDotInKeys: true)
            #expect((opts1.decode("a%2Eb", cs, .key) as? String) == "a.b")
            #expect((opts2.decode("a%2Eb", cs, .key) as? String) == "a.b")
        }
    }

    @Test("non-KEY (VALUE) decodes %2E to '.' (control)")
    func nonKeyDecodesPercentNormally() throws {
        for cs in charsets {
            let opts = DecodeOptions(allowDots: true)
            #expect((opts.decode("%2E", cs, .value) as? String) == ".")
        }
    }

    @Test("KEY maps %2E/%2e inside brackets even when allowDots=false")
    func keyMapsInsideBrackets_allowDotsFalse() throws {
        for cs in charsets {
            let opts = DecodeOptions(allowDots: false)
            #expect((opts.decode("a[%2E]", cs, .key) as? String) == "a[.]")
            #expect((opts.decode("a[%2e]", cs, .key) as? String) == "a[.]")
        }
    }

    @Test("KEY outside %2E decodes to '.' when allowDots=false (no protection outside brackets)")
    func keyOutsideBracket_allowDotsFalse() throws {
        for cs in charsets {
            let opts = DecodeOptions(allowDots: false)
            #expect((opts.decode("a%2Eb", cs, .key) as? String) == "a.b")
            #expect((opts.decode("a%2eb", cs, .key) as? String) == "a.b")
        }
    }

    @Test("decodeDotInKeys=true implies getAllowDots=true when allowDots not explicitly false")
    func decodeDotInKeysImpliesAllowDots() throws {
        let opts = DecodeOptions(decodeDotInKeys: true)
        #expect(opts.getAllowDots == true)
    }

    @Test("Decoder null return is honored (no fallback to default)")
    func decoderNilIsHonored() throws {
        let opts = DecodeOptions(decoder: { _, _, _ in nil })
        #expect(opts.decode("foo", .utf8, .value) == nil)
        #expect(opts.decode("bar", .utf8, .key) == nil)
    }

    @Test("Single decoder acts like 'legacy' when ignoring kind (no default applied first)")
    func singleDecoderBehavesLikeLegacy() throws {
        let opts = DecodeOptions(decoder: { s, _, _ in s?.uppercased() })
        #expect((opts.decode("abc", .utf8, .value) as? String) == "ABC")
        // For keys, custom decoder gets the raw token; no default percent-decoding first.
        #expect((opts.decode("a%2Eb", .utf8, .key) as? String) == "A%2EB")
    }

    @Test("copy() preserves and overrides the decoder")
    func copyPreservesAndOverridesDecoder() throws {
        let original = DecodeOptions(decoder: { s, _, k in
            guard let s else { return nil }
            let tag = (k == .key) ? "KEY" : "VALUE"
            return "K:\(tag):\(s)"
        })

        // Copy without overrides preserves decoder
        let copy1 = original.copy()
        #expect((copy1.decode("v", .utf8, .value) as? String) == "K:VALUE:v")
        #expect((copy1.decode("k", .utf8, .key) as? String) == "K:KEY:k")

        // Override the decoder
        let copy2 = original.copy(decoder: { s, _, k in
            guard let s else { return nil }
            let tag = (k == .key) ? "KEY" : "VALUE"
            return "K2:\(tag):\(s)"
        })
        #expect((copy2.decode("v", .utf8, .value) as? String) == "K2:VALUE:v")
        #expect((copy2.decode("k", .utf8, .key) as? String) == "K2:KEY:k")
    }

    @Test("decodeKey coerces non-string decoder result via String(describing:)")
    func decodeKeyCoercesNonString() throws {
        let opts = DecodeOptions(decoder: { _, _, _ in 42 })
        #expect(opts.decodeKey("anything", charset: .utf8) == "42")
    }
}

// MARK: - Charset tests

@Suite("charset")
struct CharsetDecodeTests {
    // Shared encoded constants
    let urlEncodedCheckmarkInUtf8 = "%E2%9C%93"  // ✓
    let urlEncodedOSlashInUtf8 = "%C3%B8"  // ø
    let urlEncodedNumCheckmark = "%26%2310003%3B"  // "&#10003;" percent-encoded
    let urlEncodedNumSmiley = "%26%239786%3B"  // "&#9786;" percent-encoded

    @Test("prefers UTF-8 sentinel over default ISO-8859-1")
    func sentinelPrefersUtf8OverIso() throws {
        let s =
            "utf8=\(urlEncodedCheckmarkInUtf8)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)"
        let r = try Qs.decode(s, options: .init(charset: .isoLatin1, charsetSentinel: true))
        #expect(r["ø"] as? String == "ø")
    }

    @Test("prefers ISO-8859-1 sentinel over default UTF-8")
    func sentinelPrefersIsoOverUtf8() throws {
        let s = "utf8=\(urlEncodedNumCheckmark)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)"
        let r = try Qs.decode(s, options: .init(charset: .utf8, charsetSentinel: true))
        #expect(r["Ã¸"] as? String == "Ã¸")
    }

    @Test("sentinel need not appear first")
    func sentinelOrderDoesNotMatter() throws {
        let s = "a=\(urlEncodedOSlashInUtf8)&utf8=\(urlEncodedNumCheckmark)"
        let r = try Qs.decode(s, options: .init(charset: .utf8, charsetSentinel: true))
        #expect(r["a"] as? String == "Ã¸")
    }

    @Test("ignores unknown sentinel value")
    func ignoresUnknownSentinelValue() throws {
        let s = "utf8=foo&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)"
        let r = try Qs.decode(s, options: .init(charset: .utf8, charsetSentinel: true))
        #expect(r["ø"] as? String == "ø")
    }

    @Test("sentinel switches to UTF-8 when no default charset is given")
    func sentinelSwitchesToUtf8WhenNoDefault() throws {
        let s =
            "utf8=\(urlEncodedCheckmarkInUtf8)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)"
        let r = try Qs.decode(s, options: .init(charsetSentinel: true))
        #expect(r["ø"] as? String == "ø")
    }

    @Test("sentinel switches to ISO-8859-1 when no default charset is given")
    func sentinelSwitchesToIsoWhenNoDefault() throws {
        let s = "utf8=\(urlEncodedNumCheckmark)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)"
        let r = try Qs.decode(s, options: .init(charsetSentinel: true))
        #expect(r["Ã¸"] as? String == "Ã¸")
    }

    @Test("interprets numeric entities in ISO-8859-1 when interpretNumericEntities")
    func interpretNumericEntitiesIso() throws {
        let r = try Qs.decode(
            "foo=\(urlEncodedNumSmiley)",
            options: .init(charset: .isoLatin1, interpretNumericEntities: true)
        )
        #expect(r["foo"] as? String == "☺")
    }

    @Test("custom decoder may return nil (iso-8859-1 + interpretNumericEntities)")
    func customDecoderReturningNilIso() throws {
        let decoder: ScalarDecoder = { str, charset, _ in
            guard let s = str, !s.isEmpty else { return nil }
            return Utils.decode(s, charset: charset ?? .utf8)
        }

        let r = try Qs.decode(
            "foo=&bar=\(urlEncodedNumSmiley)",
            options: .init(decoder: decoder, charset: .isoLatin1, interpretNumericEntities: true)
        )

        #expect(r["foo"] is NSNull)  // nil bridged to NSNull
        #expect(r["bar"] as? String == "☺")  // numeric entity interpreted
    }

    @Test("does not interpret numeric entities in ISO-8859-1 when flag is absent")
    func noInterpretWithoutFlagIso() throws {
        let r = try Qs.decode(
            "foo=\(urlEncodedNumSmiley)",
            options: .init(charset: .isoLatin1)
        )
        #expect(r["foo"] as? String == "&#9786;")
    }

    @Test(
        "comma:true + ISO-8859-1 + interpretNumericEntities does not crash, yields single element")
    func commaIsoDoesNotCrash() throws {
        // a[]=<comma-joined>; numeric entity should turn into "☺", and because "[]=" was used,
        // the library wraps the scalar into a single-element list.
        let r = try Qs.decode(
            "b&a[]=1,\(urlEncodedNumSmiley)",
            options: .init(charset: .isoLatin1, comma: true, interpretNumericEntities: true)
        )

        #expect(r["b"] as? String == "")
        #expect((r["a"] as? [Any])?.count == 1)
        #expect((r["a"] as? [Any])?.first as? String == "1,☺")
    }

    @Test("does not interpret numeric entities when charset is UTF-8 (even if flag set)")
    func noInterpretWhenUtf8() throws {
        let r = try Qs.decode(
            "foo=\(urlEncodedNumSmiley)",
            options: .init(charset: .utf8, interpretNumericEntities: true)
        )
        #expect(r["foo"] as? String == "&#9786;")
    }

    @Test("does not interpret %uXXXX in ISO-8859-1 mode")
    func noPercentUInIso() throws {
        let r = try Qs.decode("%u263A=%u263A", options: .init(charset: .isoLatin1))
        #expect(r["%u263A"] as? String == "%u263A")
    }
}

// MARK: - Duplicates option

@Suite("duplicates option")
struct DuplicatesTests {
    @Test("duplicates: default is .combine")
    func dupDefaultCombine() throws {
        let r = try Qs.decode("foo=bar&foo=baz")
        #expect((r["foo"] as? [String]) == ["bar", "baz"])
    }

    @Test("duplicates: .combine")
    func dupCombine() throws {
        let r = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .combine))
        #expect((r["foo"] as? [String]) == ["bar", "baz"])
    }

    @Test("duplicates: .first")
    func dupFirst() throws {
        let r = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .first))
        #expect(r["foo"] as? String == "bar")
    }

    @Test("duplicates: .last")
    func dupLast() throws {
        let r = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .last))
        #expect(r["foo"] as? String == "baz")
    }
}

// MARK: - strictDepth option

@Suite("strictDepth option")
struct StrictDepthTests {

    // Throw cases
    @Test("throws for nested objects when strictDepth = true")
    func depthThrows_Objects() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[b][c][d][e][f][g][h][i]=j",
                options: .init(depth: 1, strictDepth: true))
        } catch let e as DecodeError {
            if case .depthExceeded(let max) = e { #expect(max == 1) }
            didThrow = true
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("throws for nested lists when strictDepth = true")
    func depthThrows_Lists() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[0][1][2][3][4]=b",
                options: .init(depth: 3, strictDepth: true))
        } catch { didThrow = true }
        #expect(didThrow)
    }

    @Test("throws for mixed maps/lists when strictDepth = true")
    func depthThrows_Mixed() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[b][c][0][d][e]=f",
                options: .init(depth: 3, strictDepth: true))
        } catch { didThrow = true }
        #expect(didThrow)
    }

    @Test("throws for different value types when strictDepth = true")
    func depthThrows_DifferentTypes() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[b][c][d][e]=true&a[b][c][d][f]=42",
                options: .init(depth: 3, strictDepth: true))
        } catch { didThrow = true }
        #expect(didThrow)
    }

    // Non-throw cases
    @Test("depth = 0 with strictDepth = true does not throw")
    func depthZeroDoesNotThrow() throws {
        _ = try Qs.decode(
            "a[b][c][d][e]=true&a[b][c][d][f]=42",
            options: .init(depth: 0, strictDepth: true))
    }

    @Test("parses when depth is within limit with strictDepth = true")
    func depthWithinLimit_Strict() throws {
        let r = try Qs.decode("a[b]=c", options: .init(depth: 1, strictDepth: true))
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }

    @Test("does not throw when depth exceeds limit and strictDepth = false")
    func depthExceeds_NoStrict() throws {
        let r = try Qs.decode("a[b][c][d][e][f][g][h][i]=j", options: .init(depth: 1))
        // Expect the remainder to be treated as a literal bracketed segment
        let a = r["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        #expect((b?["[c][d][e][f][g][h][i]"] as? String) == "j")
    }

    @Test("parses when depth is within limit with strictDepth = false")
    func depthWithinLimit_NoStrict() throws {
        let r = try Qs.decode("a[b]=c", options: .init(depth: 1))
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }

    @Test("does not throw when depth is exactly at the limit with strictDepth = true")
    func depthExactlyLimit_Strict() throws {
        let r = try Qs.decode("a[b][c]=d", options: .init(depth: 2, strictDepth: true))
        let b = (r["a"] as? [String: Any])?["b"] as? [String: Any]
        #expect(b?["c"] as? String == "d")
    }
}

// MARK: - Parameter limit

@Suite("parameter limit")
struct ParameterLimitTests {
    @Test("no error within parameter limit")
    func withinLimit() throws {
        let r = try Qs.decode(
            "a=1&b=2&c=3",
            options: .init(parameterLimit: 5, throwOnLimitExceeded: true))
        #expect(r["a"] as? String == "1")
        #expect(r["b"] as? String == "2")
        #expect(r["c"] as? String == "3")
    }

    @Test("throws when parameter limit exceeded (throwOnLimitExceeded = true)")
    func limitExceededThrows() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a=1&b=2&c=3&d=4&e=5&f=6",
                options: .init(parameterLimit: 3, throwOnLimitExceeded: true))
        } catch let e as DecodeError {
            if case .parameterLimitExceeded(let limit) = e { #expect(limit == 3) }
            didThrow = true
        } catch { didThrow = true }
        #expect(didThrow)
    }

    @Test("silently truncates when throwOnLimitExceeded = false (default)")
    func truncatesWhenNotThrowing1() throws {
        let r = try Qs.decode("a=1&b=2&c=3&d=4&e=5", options: .init(parameterLimit: 3))
        #expect(r.keys.sorted() == ["a", "b", "c"])
    }

    @Test("silently truncates when parameter limit exceeded without error")
    func truncatesWhenNotThrowing2() throws {
        let r = try Qs.decode(
            "a=1&b=2&c=3&d=4&e=5",
            options: .init(parameterLimit: 3, throwOnLimitExceeded: false))
        #expect(r.keys.sorted() == ["a", "b", "c"])
    }

    @Test("allows unlimited when parameterLimit = .max")
    func unlimitedWhenMax() throws {
        let r = try Qs.decode(
            "a=1&b=2&c=3&d=4&e=5&f=6",
            options: .init(parameterLimit: .max))
        #expect(r.keys.sorted() == ["a", "b", "c", "d", "e", "f"])
    }
}

// MARK: - List limit

@Suite("list limit")
struct ListLimitTests {
    @Test("no error when list is within limit")
    func listWithinLimit() throws {
        let r = try Qs.decode(
            "a[]=1&a[]=2&a[]=3",
            options: .init(listLimit: 5, throwOnLimitExceeded: true))
        #expect((r["a"] as? [String]) == ["1", "2", "3"])
    }

    @Test("throws when list limit exceeded")
    func listLimitExceededThrows() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[]=1&a[]=2&a[]=3&a[]=4",
                options: .init(listLimit: 3, throwOnLimitExceeded: true))
        } catch let e as DecodeError {
            if case .listLimitExceeded(let limit) = e { #expect(limit == 3) }
            didThrow = true
        } catch { didThrow = true }
        #expect(didThrow)
    }

    @Test("converts list to map when index > limit")
    func listBecomesMapWhenIndexBeyondLimit() throws {
        let r = try Qs.decode(
            "a[1]=1&a[2]=2&a[3]=3&a[4]=4&a[5]=5&a[6]=6",
            options: .init(listLimit: 5))
        let a = r["a"] as? [String: Any]
        #expect(a?["1"] as? String == "1")
        #expect(a?["6"] as? String == "6")
        #expect(a?.count == 6)
    }

    @Test("handles list limit of zero correctly")
    func listLimitZero() throws {
        let r = try Qs.decode("a[]=1&a[]=2", options: .init(listLimit: 0))
        let a = asDictString(r["a"])
        #expect((a?["0"] as? String) == "1")
        #expect((a?["1"] as? String) == "2")
        #expect(a?.count == 2)
    }

    @Test("list limit applies to [] overflow")
    func listLimitAppliesToEmptyBracketOverflow() throws {
        let attack = Array(repeating: "a[]=x", count: 105).joined(separator: "&")
        let result = try Qs.decode(attack, options: .init(listLimit: 100))
        let a = asDictString(result["a"])
        #expect(a?.count == 105)
        #expect((a?["0"] as? String) == "x")
        #expect((a?["104"] as? String) == "x")
    }

    @Test("list limit boundary conditions for []")
    func listLimitBoundaryConditions() throws {
        do {
            let result = try Qs.decode(
                "a[]=1&a[]=2&a[]=3",
                options: .init(listLimit: 3))
            #expect(asStrings(result["a"]) == ["1", "2", "3"])
        }
        do {
            let result = try Qs.decode(
                "a[]=1&a[]=2&a[]=3&a[]=4",
                options: .init(listLimit: 3))
            let a = asDictString(result["a"])
            #expect((a?["0"] as? String) == "1")
            #expect((a?["3"] as? String) == "4")
            #expect(a?.count == 4)
        }
        do {
            let result = try Qs.decode(
                "a[]=1&a[]=2",
                options: .init(listLimit: 1))
            let a = asDictString(result["a"])
            #expect((a?["0"] as? String) == "1")
            #expect((a?["1"] as? String) == "2")
            #expect(a?.count == 2)
        }
    }

    @Test("list limit applies to duplicate keys")
    func listLimitAppliesToDuplicateKeys() throws {
        let under = try Qs.decode("a=b&a=c&a=d", options: .init(listLimit: 20))
        #expect(asStrings(under["a"]) == ["b", "c", "d"])

        let over = try Qs.decode("a=b&a=c&a=d", options: .init(listLimit: 2))
        let a = asDictString(over["a"])
        #expect((a?["0"] as? String) == "b")
        #expect((a?["2"] as? String) == "d")
        #expect(a?.count == 3)
    }

    @Test("negative list limit throws (when throwOnLimitExceeded = true)")
    func negativeListLimitThrows() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[]=1&a[]=2",
                options: .init(listLimit: -1, throwOnLimitExceeded: true))
        } catch { didThrow = true }
        #expect(didThrow)
    }

    @Test("applies list limit to nested lists")
    func nestedListsRespectLimit() {
        var didThrow = false
        do {
            _ = try Qs.decode(
                "a[0][]=1&a[0][]=2&a[0][]=3&a[0][]=4",
                options: .init(listLimit: 3, throwOnLimitExceeded: true))
        } catch { didThrow = true }
        #expect(didThrow)
    }
}

// MARK: - Ported from https://github.com/atek-software/qsparser

extension DecodeTests {

    // MARK: simple strings

    @Test("parse: simple strings")
    func parse_simpleStrings() throws {
        let opt = DecodeOptions()
        let optStrict = DecodeOptions(strictNullHandling: true)

        var r = try Qs.decode("0=foo", options: opt)
        #expect(r["0"] as? String == "foo")

        r = try Qs.decode("foo=c++", options: opt)
        #expect(r["foo"] as? String == "c  ")

        r = try Qs.decode("a[>=]=23", options: opt)
        #expect(((r["a"] as? [String: Any])?[">="] as? String) == "23")

        r = try Qs.decode("a[<=>]==23", options: opt)
        #expect(((r["a"] as? [String: Any])?["<=>"] as? String) == "=23")

        r = try Qs.decode("a[==]=23", options: opt)
        #expect(((r["a"] as? [String: Any])?["=="] as? String) == "23")

        r = try Qs.decode("foo", options: optStrict)
        #expect(r["foo"] is NSNull)

        r = try Qs.decode("foo", options: opt)
        #expect(r["foo"] as? String == "")

        r = try Qs.decode("foo=", options: opt)
        #expect(r["foo"] as? String == "")

        r = try Qs.decode("foo=bar", options: opt)
        #expect(r["foo"] as? String == "bar")

        r = try Qs.decode(" foo = bar = baz ", options: opt)
        #expect(r[" foo "] as? String == " bar = baz ")

        r = try Qs.decode("foo=bar=baz", options: opt)
        #expect(r["foo"] as? String == "bar=baz")

        r = try Qs.decode("foo=bar&bar=baz", options: opt)
        #expect(r["foo"] as? String == "bar")
        #expect(r["bar"] as? String == "baz")

        r = try Qs.decode("foo2=bar2&baz2=", options: opt)
        #expect(r["foo2"] as? String == "bar2")
        #expect(r["baz2"] as? String == "")

        r = try Qs.decode("foo=bar&baz", options: optStrict)
        #expect(r["foo"] as? String == "bar")
        #expect(r["baz"] is NSNull)

        r = try Qs.decode("foo=bar&baz", options: opt)
        #expect(r["foo"] as? String == "bar")
        #expect(r["baz"] as? String == "")

        r = try Qs.decode("cht=p3&chd=t:60,40&chs=250x100&chl=Hello|World", options: opt)
        #expect(r["cht"] as? String == "p3")
        #expect(r["chd"] as? String == "t:60,40")
        #expect(r["chs"] as? String == "250x100")
        #expect(r["chl"] as? String == "Hello|World")
    }

    // MARK: arrays on same key

    @Test("parse: arrays on the same key")
    func parse_arraysSameKey() throws {
        let opt = DecodeOptions()

        var r = try Qs.decode("a[]=b&a[]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)
        #expect((r["a"] as? [Any])?[0] as? String == "b")
        #expect((r["a"] as? [Any])?[1] as? String == "c")

        r = try Qs.decode("a[0]=b&a[1]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)
        #expect((r["a"] as? [Any])?[0] as? String == "b")
        #expect((r["a"] as? [Any])?[1] as? String == "c")

        r = try Qs.decode("a=b,c", options: opt)
        #expect(r["a"] as? String == "b,c")

        r = try Qs.decode("a=b&a=c", options: opt)
        let a = r["a"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?[0] as? String == "b")
        #expect(a?[1] as? String == "c")
    }

    // MARK: dot notation

    @Test("parse: dot notation")
    func parse_allowDots() throws {
        let plain = DecodeOptions()
        let allow = DecodeOptions(allowDots: true)

        var r = try Qs.decode("a.b=c", options: plain)
        #expect(r["a.b"] as? String == "c")

        r = try Qs.decode("a.b=c", options: allow)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }

    // MARK: depth parsing

    @Test("parse: depth parsing")
    func parse_depth() throws {
        let opt = DecodeOptions()
        let d1 = DecodeOptions(depth: 1)
        let d0 = DecodeOptions(depth: 0)

        var r = try Qs.decode("a[b]=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")

        r = try Qs.decode("a[b][c]=d", options: opt)
        #expect((((r["a"] as? [String: Any])?["b"] as? [String: Any])?["c"] as? String) == "d")

        r = try Qs.decode("a[b][c][d][e][f][g][h]=i", options: opt)
        let longB = ((r["a"] as? [String: Any])?["b"] as? [String: Any])
        let longC = longB?["c"] as? [String: Any]
        let longD = longC?["d"] as? [String: Any]
        let longE = longD?["e"] as? [String: Any]
        let longF = longE?["f"] as? [String: Any]
        let tail = longF?["[g][h]"] as? String
        #expect(tail == "i")

        r = try Qs.decode("a[b][c]=d", options: d1)
        #expect(((r["a"] as? [String: Any])?["b"] as? [String: Any])?["[c]"] as? String == "d")

        r = try Qs.decode("a[b][c][d]=e", options: d1)
        #expect(((r["a"] as? [String: Any])?["b"] as? [String: Any])?["[c][d]"] as? String == "e")

        r = try Qs.decode("a[0]=b&a[1]=c", options: d0)
        #expect(r["a[0]"] as? String == "b")
        #expect(r["a[1]"] as? String == "c")

        r = try Qs.decode("a[0][0]=b&a[0][1]=c&a[1]=d&e=2", options: d0)
        #expect(r["a[0][0]"] as? String == "b")
        #expect(r["a[0][1]"] as? String == "c")
        #expect(r["a[1]"] as? String == "d")
        #expect(r["e"] as? String == "2")
    }

    // MARK: explicit arrays

    @Test("parse: explicit arrays")
    func parse_explicitArrays() throws {
        let opt = DecodeOptions()

        var r = try Qs.decode("a[]=b", options: opt)
        #expect((r["a"] as? [Any])?.count == 1)
        #expect((r["a"] as? [Any])?.first as? String == "b")

        r = try Qs.decode("a[]=b&a[]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[]=b&a[]=c&a[]=d", options: opt)
        #expect((r["a"] as? [Any])?.count == 3)
    }

    // MARK: mix of simple and explicit arrays

    @Test("parse: mix simple + explicit arrays")
    func parse_mixArrays() throws {
        let opt = DecodeOptions()
        let opt20 = DecodeOptions(listLimit: 20)
        let opt0 = DecodeOptions(listLimit: 0)

        var r = try Qs.decode("a=b&a[]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[]=b&a=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[0]=b&a=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a=b&a[0]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[1]=b&a=c", options: opt20)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[]=b&a=c", options: opt0)
        do {
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "c")
            #expect(a?.count == 2)
        }

        r = try Qs.decode("a=b&a[1]=c", options: opt20)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a=b&a[]=c", options: opt0)
        do {
            let a = asDictString(r["a"])
            #expect((a?["0"] as? String) == "b")
            #expect((a?["1"] as? String) == "c")
            #expect(a?.count == 2)
        }
    }

    // MARK: nested arrays

    @Test("parse: nested arrays")
    func parse_nestedArrays() throws {
        let opt = DecodeOptions()

        var r = try Qs.decode("a[b][]=c&a[b][]=d", options: opt)
        let ab = (r["a"] as? [String: Any])?["b"] as? [Any]
        #expect((ab?[0] as? String) == "c")
        #expect((ab?[1] as? String) == "d")

        r = try Qs.decode("a[>=]=25", options: opt)
        #expect(((r["a"] as? [String: Any])?["\u{003E}="] as? String) == "25")
    }

    // MARK: array indices

    @Test("parse: allow specifying array indices")
    func parse_arrayIndices() throws {
        let opt = DecodeOptions()
        let opt20 = DecodeOptions(listLimit: 20)
        let opt0 = DecodeOptions(listLimit: 0)

        var r = try Qs.decode("a[1]=c&a[0]=b&a[2]=d", options: opt)
        let a = r["a"] as? [Any]
        #expect(a?.count == 3)
        #expect(a?[0] as? String == "b")
        #expect(a?[1] as? String == "c")
        #expect(a?[2] as? String == "d")

        r = try Qs.decode("a[1]=c&a[0]=b", options: opt)
        let a2 = r["a"] as? [Any]
        #expect(a2?.count == 2)
        #expect(a2?[0] as? String == "b")
        #expect(a2?[1] as? String == "c")

        r = try Qs.decode("a[1]=c", options: opt20)
        #expect((r["a"] as? [Any])?.count == 1)
        #expect((r["a"] as? [Any])?.first as? String == "c")

        r = try Qs.decode("a[1]=c", options: opt0)
        #expect(((r["a"] as? [String: Any])?["1"] as? String) == "c")

        r = try Qs.decode("a[1]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 1)
    }

    // MARK: listLimit vs indices

    @Test("parse: limit specific array indices to listLimit")
    func parse_listLimitIndexing() throws {
        let optDefault = DecodeOptions()  // listLimit = 20
        let opt20 = DecodeOptions(listLimit: 20)

        // index == listLimit ⇒ still an array (compacted to one element)
        var r = try Qs.decode("a[20]=a", options: opt20)
        #expect((r["a"] as? [Any])?.count == 1)
        #expect((r["a"] as? [Any])?.first as? String == "a")

        // index > listLimit ⇒ becomes a map keyed by the index
        r = try Qs.decode("a[21]=a", options: opt20)
        #expect(((r["a"] as? [String: Any])?["21"] as? String) == "a")

        // Same expectations with default options (listLimit defaults to 20)
        r = try Qs.decode("a[20]=a", options: optDefault)
        #expect((r["a"] as? [Any])?.count == 1)
        #expect((r["a"] as? [Any])?.first as? String == "a")

        r = try Qs.decode("a[21]=a", options: optDefault)
        #expect(((r["a"] as? [String: Any])?["21"] as? String) == "a")
    }

    // MARK: numeric-leading keys

    @Test("parse: keys that begin with a number")
    func parse_numericLeadingKeys() throws {
        let r = try Qs.decode("a[12b]=c")
        #expect(((r["a"] as? [String: Any])?["12b"] as? String) == "c")
    }

    // MARK: encoded equal signs

    @Test("parse: encoded equal signs")
    func parse_encodedEquals() throws {
        let r = try Qs.decode("he%3Dllo=th%3Dere")
        #expect(r["he=llo"] as? String == "th=ere")
    }

    // MARK: URL-encoded strings

    @Test("parse: URL-encoded strings")
    func parse_urlEncoded() throws {
        var r = try Qs.decode("a[b%20c]=d")
        #expect(((r["a"] as? [String: Any])?["b c"] as? String) == "d")

        r = try Qs.decode("a[b]=c%20d")
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c d")
    }

    // MARK: brackets in value

    @Test("parse: allow brackets in value")
    func parse_bracketsInValue() throws {
        var r = try Qs.decode("pets=[\"tobi\"]")
        #expect(r["pets"] as? String == "[\"tobi\"]")

        r = try Qs.decode("operators=[\">=\", \"<=\"]")
        #expect(r["operators"] as? String == "[\">=\", \"<=\"]")
    }

    // MARK: empty values

    @Test("parse: empty values")
    func parse_emptyValues() throws {
        let r1 = try Qs.decode("")
        #expect(r1.isEmpty)

        let r2 = try Qs.decode(nil as Any?)
        #expect(r2.isEmpty)
    }

    // MARK: transform arrays to objects

    @Test("parse: transform arrays to objects")
    func parse_transformArraysToObjects() throws {
        var r = try Qs.decode("foo[0]=bar&foo[bad]=baz")
        var foo = r["foo"] as? [String: Any]
        #expect(foo?["0"] as? String == "bar")
        #expect(foo?["bad"] as? String == "baz")

        r = try Qs.decode("foo[bad]=baz&foo[0]=bar")
        foo = r["foo"] as? [String: Any]
        #expect(foo?["bad"] as? String == "baz")
        #expect(foo?["0"] as? String == "bar")

        r = try Qs.decode("foo[bad]=baz&foo[]=bar")
        foo = r["foo"] as? [String: Any]
        #expect(foo?["bad"] as? String == "baz")
        #expect(foo?["0"] as? String == "bar")

        r = try Qs.decode("foo[]=bar&foo[bad]=baz")
        foo = r["foo"] as? [String: Any]
        #expect(foo?["0"] as? String == "bar")
        #expect(foo?["bad"] as? String == "baz")

        r = try Qs.decode("foo[bad]=baz&foo[]=bar&foo[]=foo")
        foo = r["foo"] as? [String: Any]
        #expect(foo?["bad"] as? String == "baz")
        #expect(foo?["0"] as? String == "bar")
        #expect(foo?["1"] as? String == "foo")

        r = try Qs.decode("foo[0][a]=a&foo[0][b]=b&foo[1][a]=aa&foo[1][b]=bb")
        let arr = r["foo"] as? [Any]
        let m0 = arr?[0] as? [String: Any]
        let m1 = arr?[1] as? [String: Any]
        #expect(m0?["a"] as? String == "a")
        #expect(m0?["b"] as? String == "b")
        #expect(m1?["a"] as? String == "aa")
        #expect(m1?["b"] as? String == "bb")
    }

    // MARK: transform arrays to objects + allowDots

    @Test("parse: transform arrays to objects with dot notation")
    func parse_transformWithDots() throws {
        let allow = DecodeOptions(allowDots: true)

        var r = try Qs.decode("foo[0].baz=bar&fool.bad=baz", options: allow)
        var foo = r["foo"] as? [Any]
        var m0 = foo?.first as? [String: Any]
        #expect(m0?["baz"] as? String == "bar")
        #expect(((r["fool"] as? [String: Any])?["bad"] as? String) == "baz")

        r = try Qs.decode("foo[0].baz=bar&fool.bad.boo=baz", options: allow)
        foo = r["foo"] as? [Any]
        m0 = foo?.first as? [String: Any]
        #expect(m0?["baz"] as? String == "bar")
        let fool = r["fool"] as? [String: Any]
        #expect(((fool?["bad"] as? [String: Any])?["boo"] as? String) == "baz")

        r = try Qs.decode("foo[0][0].baz=bar&fool.bad=baz", options: allow)
        foo = r["foo"] as? [Any]
        let inner = foo?.first as? [Any]
        let innerMap = inner?.first as? [String: Any]
        #expect(innerMap?["baz"] as? String == "bar")
        #expect(((r["fool"] as? [String: Any])?["bad"] as? String) == "baz")

        r = try Qs.decode("foo[0].baz[0]=15&foo[0].bar=2", options: allow)
        foo = r["foo"] as? [Any]
        m0 = foo?.first as? [String: Any]
        let baz = m0?["baz"] as? [Any]
        #expect(baz?.first as? String == "15")
        #expect(m0?["bar"] as? String == "2")

        r = try Qs.decode("foo[0].baz[0]=15&foo[0].baz[1]=16&foo[0].bar=2", options: allow)
        foo = r["foo"] as? [Any]
        m0 = foo?.first as? [String: Any]
        let baz2 = m0?["baz"] as? [Any]
        #expect(baz2?.count == 2)
        #expect(baz2?[0] as? String == "15")
        #expect(baz2?[1] as? String == "16")
        #expect(m0?["bar"] as? String == "2")

        r = try Qs.decode("foo.bad=baz&foo[0]=bar", options: allow)
        let fooMixed = r["foo"] as? [String: Any]
        #expect(fooMixed?["bad"] as? String == "baz")
        #expect(fooMixed?["0"] as? String == "bar")

        r = try Qs.decode("foo.bad=baz&foo[]=bar", options: allow)
        let fooMixed2 = r["foo"] as? [String: Any]
        #expect(fooMixed2?["bad"] as? String == "baz")
        #expect(fooMixed2?["0"] as? String == "bar")

        r = try Qs.decode("foo[]=bar&foo.bad=baz", options: allow)
        let fooMixed3 = r["foo"] as? [String: Any]
        #expect(fooMixed3?["0"] as? String == "bar")
        #expect(fooMixed3?["bad"] as? String == "baz")

        r = try Qs.decode("foo.bad=baz&foo[]=bar&foo[]=foo", options: allow)
        let fooMixed4 = r["foo"] as? [String: Any]
        #expect(fooMixed4?["bad"] as? String == "baz")
        #expect(fooMixed4?["0"] as? String == "bar")
        #expect(fooMixed4?["1"] as? String == "foo")

        r = try Qs.decode("foo[0].a=a&foo[0].b=b&foo[1].a=aa&foo[1].b=bb", options: allow)
        let arr = r["foo"] as? [Any]
        let mA0 = arr?[0] as? [String: Any]
        let mA1 = arr?[1] as? [String: Any]
        #expect(mA0?["a"] as? String == "a")
        #expect(mA0?["b"] as? String == "b")
        #expect(mA1?["a"] as? String == "aa")
        #expect(mA1?["b"] as? String == "bb")
    }

    // MARK: prune undefined

    @Test("parse: correctly prune undefined values")
    func parse_pruneUndefined() throws {
        let r = try Qs.decode("a[2]=b&a[99999999]=c")
        let a = r["a"] as? [String: Any]
        #expect(a?["2"] as? String == "b")
        #expect(a?["99999999"] as? String == "c")
    }

    // MARK: malformed URI characters

    @Test("parse: support malformed URI characters")
    func parse_malformed() throws {
        var r = try Qs.decode("{%:%}", options: DecodeOptions(strictNullHandling: true))
        #expect(r["{%:%}"] is NSNull)

        r = try Qs.decode("{%:%}=")
        #expect(r["{%:%}"] as? String == "")

        r = try Qs.decode("foo=%:%}")
        #expect(r["foo"] as? String == "%:%}")
    }

    // MARK: no empty keys from trailing delimiter

    @Test("parse: no empty keys from trailing delimiter")
    func parse_noEmptyKeys() throws {
        let r = try Qs.decode("_r=1&")
        #expect(r.count == 1)
        #expect(r["_r"] as? String == "1")
    }

    // MARK: arrays of objects

    @Test("parse: arrays of objects")
    func parse_arraysOfObjects() throws {
        var r = try Qs.decode("a[][b]=c")
        var a = r["a"] as? [Any]
        #expect(((a?.first as? [String: Any])?["b"] as? String) == "c")

        r = try Qs.decode("a[0][b]=c")
        a = r["a"] as? [Any]
        #expect(((a?.first as? [String: Any])?["b"] as? String) == "c")
    }

    // MARK: empty strings in arrays

    @Test("parse: allow empty strings in arrays")
    func parse_emptyStringsInArrays() throws {
        let opt = DecodeOptions()
        let optStrict20 = DecodeOptions(listLimit: 20, strictNullHandling: true)
        let optStrict0 = DecodeOptions(listLimit: 0, strictNullHandling: true)

        var r = try Qs.decode("a[]=b&a[]=&a[]=c", options: opt)
        #expect((r["a"] as? [Any])?.count == 3)
        #expect((r["a"] as? [Any])?[1] as? String == "")

        r = try Qs.decode("a[0]=b&a[1]&a[2]=c&a[19]=", options: optStrict20)
        let a1 = r["a"] as? [Any]
        #expect(a1?[0] as? String == "b")
        #expect(a1?[1] is NSNull)
        #expect(a1?[2] as? String == "c")
        #expect(a1?.last as? String == "")

        r = try Qs.decode("a[]=b&a[]&a[]=c&a[]=", options: optStrict0)
        let a2 = asDictString(r["a"])
        #expect(a2?["0"] as? String == "b")
        #expect(isNSNullValue(a2?["1"]))
        #expect(a2?["2"] as? String == "c")
        #expect(a2?["3"] as? String == "")

        r = try Qs.decode("a[0]=b&a[1]=&a[2]=c&a[19]", options: optStrict20)
        let a3 = r["a"] as? [Any]
        #expect(a3?[0] as? String == "b")
        #expect(a3?[1] as? String == "")
        #expect(a3?[2] as? String == "c")
        #expect(a3?.last is NSNull)

        r = try Qs.decode("a[]=b&a[]=&a[]=c&a[]", options: optStrict0)
        let a4 = asDictString(r["a"])
        #expect(a4?["0"] as? String == "b")
        #expect(a4?["1"] as? String == "")
        #expect(a4?["2"] as? String == "c")
        #expect(isNSNullValue(a4?["3"]))

        r = try Qs.decode("a[]=&a[]=b&a[]=c", options: optStrict0)
        let a5 = asDictString(r["a"])
        #expect(a5?["0"] as? String == "")
        #expect(a5?["1"] as? String == "b")
        #expect(a5?["2"] as? String == "c")
    }

    // MARK: compact arrays (no sparse)

    @Test("parse: compact sparse arrays")
    func parse_compactSparse() throws {
        let opt = DecodeOptions(listLimit: 20)

        var r = try Qs.decode("a[10]=1&a[2]=2", options: opt)
        let a = r["a"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?[0] as? String == "2")
        #expect(a?[1] as? String == "1")

        r = try Qs.decode("a[1][b][2][c]=1", options: opt)
        #expect(((r["a"] as? [Any])?.first as? [String: Any])?["b"] != nil)

        r = try Qs.decode("a[1][2][3][c]=1", options: opt)
        #expect(r["a"] is [Any])

        r = try Qs.decode("a[1][2][3][c][1]=1", options: opt)
        #expect(r["a"] is [Any])
    }

    // MARK: allowSparse

    @Test("parse: sparse arrays (allowSparseLists)")
    func parse_sparseArrays() throws {
        let allowSparse = DecodeOptions(allowSparseLists: true)

        var r = try Qs.decode("a[4]=1&a[1]=2", options: allowSparse)
        let a = r["a"] as? [Any]
        #expect(a?.count == 5)
        #expect(a?[0] is NSNull)
        #expect(a?[1] as? String == "2")
        #expect(a?[4] as? String == "1")

        r = try Qs.decode("a[1][b][2][c]=1", options: allowSparse)
        #expect(r["a"] is [Any])

        r = try Qs.decode("a[1][2][3][c]=1", options: allowSparse)
        #expect(r["a"] is [Any])

        r = try Qs.decode("a[1][2][3][c][1]=1", options: allowSparse)
        #expect(r["a"] is [Any])
    }

    // MARK: jQuery-style params

    @Test("parse: jQuery param strings")
    func parse_jquery() throws {
        let r = try Qs.decode(
            "filter%5B0%5D%5B%5D=int1&filter%5B0%5D%5B%5D=%3D&filter%5B0%5D%5B%5D=77&filter%5B%5D=and&filter%5B2%5D%5B%5D=int2&filter%5B2%5D%5B%5D=%3D&filter%5B2%5D%5B%5D=8"
        )
        let filter = r["filter"] as? [Any]
        #expect((filter?[0] as? [Any])?.count == 3)
        #expect(filter?[1] as? String == "and")
        #expect((filter?[2] as? [Any])?.count == 3)
    }

    // MARK: continue when no parent is found

    @Test("parse: continue when no parent is found")
    func parse_noParent() throws {
        let opt = DecodeOptions()
        let strict = DecodeOptions(strictNullHandling: true)

        var r = try Qs.decode("[]=&a=b", options: opt)
        #expect(r["0"] as? String == "")
        #expect(r["a"] as? String == "b")

        r = try Qs.decode("[]=&a=b", options: DecodeOptions(listLimit: 0))
        #expect(r["0"] as? String == "")
        #expect(r["a"] as? String == "b")

        r = try Qs.decode("[]&a=b", options: strict)
        #expect(r["0"] is NSNull)
        #expect(r["a"] as? String == "b")

        r = try Qs.decode("[foo]=bar", options: strict)
        #expect(r["foo"] as? String == "bar")
    }

    // MARK: very long array

    @Test("parse: does not crash on very long array")
    func parse_longArray() {
        var atom = "a[]=a"
        while atom.count < 120 * 1024 {
            atom += "&" + atom
        }
        #expect((try? Qs.decode(atom)) != nil)
    }

    // MARK: alternative delimiters

    @Test("parse: alternative string/regex delimiter")
    func parse_altDelimiter() throws {
        let semi = DecodeOptions(delimiter: StringDelimiter(";"))
        let both = DecodeOptions(delimiter: try RegexDelimiter("[;,] *"))

        var r = try Qs.decode("a=b;c=d", options: semi)
        #expect(r["a"] as? String == "b")
        #expect(r["c"] as? String == "d")

        r = try Qs.decode("a=b; c=d", options: both)  // <- needs `try` here too
        #expect(r["a"] as? String == "b")
        #expect(r["c"] as? String == "d")
    }

    // MARK: override parameter limit

    @Test("parse: override parameter limit")
    func parse_paramLimit() throws {
        let one = DecodeOptions(parameterLimit: 1)
        let max = DecodeOptions(parameterLimit: .max)  // Int.max

        var r = try Qs.decode("a=b&c=d", options: one)
        #expect(r["a"] as? String == "b")
        #expect(r["c"] == nil)

        r = try Qs.decode("a=b&c=d", options: max)
        #expect(r["a"] as? String == "b")
        #expect(r["c"] as? String == "d")
    }

    // MARK: override list limit (negative)

    @Test("parse: override list limit (negative)")
    func parse_listLimitNegative() throws {
        let neg = DecodeOptions(listLimit: -1)

        var r = try Qs.decode("a[0]=b", options: neg)
        #expect(((r["a"] as? [String: Any])?["0"] as? String) == "b")

        r = try Qs.decode("a[-1]=b", options: neg)
        #expect(((r["a"] as? [String: Any])?["-1"] as? String) == "b")

        r = try Qs.decode("a[0]=b&a[1]=c", options: neg)
        let a = r["a"] as? [String: Any]
        #expect(a?["0"] as? String == "b")
        #expect(a?["1"] as? String == "c")
    }

    // MARK: disable list parsing

    @Test("parse: disable list parsing")
    func parse_disableLists() throws {
        let opt = DecodeOptions(parseLists: false)

        var r = try Qs.decode("a[0]=b&a[1]=c", options: opt)
        let a = r["a"] as? [String: Any]
        #expect(a?["0"] as? String == "b")
        #expect(a?["1"] as? String == "c")

        r = try Qs.decode("a[]=b", options: opt)
        let a2 = r["a"] as? [String: Any]
        #expect(a2?["0"] as? String == "b")
    }

    // MARK: query prefix

    @Test("parse: query string prefix handling")
    func parse_queryPrefix() throws {
        let ignore = DecodeOptions(ignoreQueryPrefix: true)
        let keep = DecodeOptions(ignoreQueryPrefix: false)

        var r = try Qs.decode("?foo=bar", options: ignore)
        #expect(r["foo"] as? String == "bar")

        r = try Qs.decode("foo=bar", options: ignore)
        #expect(r["foo"] as? String == "bar")

        r = try Qs.decode("?foo=bar", options: keep)
        #expect(r["?foo"] as? String == "bar")
    }

    // MARK: comma as array divider

    @Test("parse: comma as array divider")
    func parse_commaArrays() throws {
        let simple = DecodeOptions()
        let comma = DecodeOptions(comma: true)
        let commaStrictNull = DecodeOptions(comma: true, strictNullHandling: true)

        var r = try Qs.decode("foo=bar,tee", options: comma)
        let a = r["foo"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?[0] as? String == "bar")
        #expect(a?[1] as? String == "tee")

        r = try Qs.decode("foo[bar]=coffee,tee", options: comma)
        let nested = (r["foo"] as? [String: Any])?["bar"] as? [Any]
        #expect(nested?.count == 2)
        #expect(nested?[0] as? String == "coffee")
        #expect(nested?[1] as? String == "tee")

        r = try Qs.decode("foo=", options: comma)
        #expect(r["foo"] as? String == "")

        r = try Qs.decode("foo", options: comma)
        #expect(r["foo"] as? String == "")

        r = try Qs.decode("foo", options: commaStrictNull)
        #expect(r["foo"] is NSNull)

        r = try Qs.decode("a[0]=c", options: simple)
        #expect((r["a"] as? [Any])?.first as? String == "c")

        r = try Qs.decode("a[]=c", options: simple)
        #expect((r["a"] as? [Any])?.first as? String == "c")

        r = try Qs.decode("a[]=c", options: comma)
        #expect((r["a"] as? [Any])?.first as? String == "c")

        r = try Qs.decode("a[0]=c&a[1]=d", options: simple)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[]=c&a[]=d", options: simple)
        #expect((r["a"] as? [Any])?.count == 2)

        r = try Qs.decode("a[]=c&a[]=d", options: comma)
        #expect((r["a"] as? [Any])?.count == 2)
    }

    // MARK: custom number decoder

    @Test("parse: number decoder")
    func parse_numberDecoder() throws {
        let numberDecoder: ScalarDecoder = { value, _, _ in
            if let v = value, let n = Int(v) { return "[\(n)]" }
            return value
        }
        let opt = DecodeOptions(decoder: numberDecoder)

        var r = try Qs.decode("foo=1", options: opt)
        #expect(r["foo"] as? String == "[1]")

        r = try Qs.decode("foo=1.0", options: opt)
        #expect(r["foo"] as? String == "1.0")

        r = try Qs.decode("foo=0", options: opt)
        #expect(r["foo"] as? String == "[0]")
    }

    // MARK: comma-delimited arrays with encoding

    @Test("parse: comma-delimited array with %2C")
    func parse_commaPercent() throws {
        let opt = DecodeOptions(comma: true)

        var r = try Qs.decode("foo=a%2Cb", options: opt)
        #expect(r["foo"] as? String == "a,b")

        r = try Qs.decode("foo=a%2C%20b,d", options: opt)
        let a = r["foo"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?[0] as? String == "a, b")
        #expect(a?[1] as? String == "d")

        r = try Qs.decode("foo=a%2C%20b,c%2C%20d", options: opt)
        let b = r["foo"] as? [Any]
        #expect(b?.count == 2)
        #expect(b?[0] as? String == "a, b")
        #expect(b?[1] as? String == "c, d")
    }

    // MARK: deep objects not crash

    @Test("parse: deep objects do not crash (500)")
    func parse_deepObjects() {
        var s = "foo"
        for _ in 0..<500 { s += "[p]" }
        s += "=bar"

        let opt = DecodeOptions(depth: 500)
        let r = try? Qs.decode(s, options: opt)
        #expect(r != nil)

        var depth = 0
        var node: Any? = r?["foo"]
        while let d = node as? [String: Any], let next = d["p"] {
            node = next
            depth += 1
        }
        #expect(depth == 500)
    }

    // MARK: params starting with closing bracket

    @Test("parse: params starting with a closing bracket")
    func parse_startsWithCloseBracket() throws {
        var r = try Qs.decode("]=toString")
        #expect(r["]"] as? String == "toString")

        r = try Qs.decode("]]=toString")
        #expect(r["]]"] as? String == "toString")

        r = try Qs.decode("]hello]=toString")
        #expect(r["]hello]"] as? String == "toString")
    }

    // MARK: params starting with starting bracket

    @Test("parse: params starting with a starting bracket")
    func parse_startsWithOpenBracket() throws {
        var r = try Qs.decode("[=toString")
        #expect(r["["] as? String == "toString")

        r = try Qs.decode("[[=toString")
        #expect(r["[["] as? String == "toString")

        r = try Qs.decode("[hello[=toString")
        #expect(r["[hello["] as? String == "toString")
    }

    // MARK: add keys to objects

    @Test("parse: add keys to objects")
    func parse_addKeys() throws {
        let r = try Qs.decode("a[b]=c&a=d")
        let a = r["a"] as? [String: Any]
        #expect(a?["b"] as? String == "c")
        #expect(a?["d"] as? Bool == true)
    }

    // MARK: custom encoding (Shift_JIS)

    @Test("parse: custom encoding (Shift_JIS)")
    func parse_customShiftJIS() throws {
        #if os(Linux)
            // Try a real Shift_JIS decode. If it fails, record as a known issue; if it succeeds, assert normally.
            let bytes: [UInt8] = [0x91, 0xE5, 0x8D, 0xE3, 0x95, 0x7B]  // "大阪府" in Shift_JIS
            let decoded = String(data: Data(bytes), encoding: .shiftJIS)
            if decoded == "大阪府" {
                // It works on this Linux runtime — pass normally (do not use withKnownIssue).
                #expect(decoded == "大阪府")
            } else {
                try withKnownIssue("Got: \(decoded.debugDescription)") {
                    // Expected failure on Linux today: Shift_JIS decoding often unavailable in corelibs-foundation.
                    // If/when this ever starts working, the branch above will exercise instead.
                    #expect(decoded == "大阪府")
                }
            }
            return
        #endif
        // Local helper needs to be @Sendable if captured by a @Sendable closure.
        @Sendable
        func percentDecode(_ s: String, encoding: String.Encoding) -> String? {
            // Replace '+' with space (www-form-urlencoded)
            let replaced = s.replacingOccurrences(of: "+", with: " ")

            // Percent-decode into raw bytes (no UTF-8 interpretation yet)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(replaced.utf8.count)

            let u = Array(replaced.utf8)
            var i = 0
            while i < u.count {
                if u[i] == UInt8(ascii: "%"), i + 2 < u.count,
                    let h1 = hexNibble(u[i + 1]), let h2 = hexNibble(u[i + 2])
                {
                    bytes.append(UInt8((h1 << 4) | h2))
                    i += 3
                } else {
                    bytes.append(u[i])
                    i += 1
                }
            }

            // Now interpret the bytes as Shift_JIS text.
            return String(data: Data(bytes), encoding: encoding)
        }

        // Make the closure type explicitly @Sendable.
        let decoder: @Sendable (String?, String.Encoding?, DecodeKind?) -> Any? = { s, _, _ in
            guard let s else { return nil }
            return percentDecode(s, encoding: .shiftJIS) ?? s
        }

        let opt = DecodeOptions(decoder: decoder)

        let r = try Qs.decode("%8c%a7=%91%e5%8d%e3%95%7b", options: opt)
        #expect(r["県"] as? String == "大阪府")
    }

    // Tiny hex helper for the percent-decoder
    private func hexNibble(_ b: UInt8) -> Int? {
        switch b {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(b - UInt8(ascii: "0"))
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(b - UInt8(ascii: "A")) + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(b - UInt8(ascii: "a")) + 10
        default: return nil
        }
    }

    // MARK: - parse other charset

    @Test("parse: other charset iso-8859-1")
    func parse_otherCharset() throws {
        let r = try Qs.decode("%A2=%BD", options: .init(charset: .isoLatin1))
        #expect(r["¢"] as? String == "½")
    }

    // MARK: - charset sentinel (dup of charset suite, kept for parity)

    @Test("parse: charset sentinel variants")
    func parse_charsetSentinel() throws {
        let urlEncodedCheckmarkInUtf8 = "%E2%9C%93"
        let urlEncodedOSlashInUtf8 = "%C3%B8"
        let urlEncodedNumCheckmark = "%26%2310003%3B"

        let iso = DecodeOptions(charset: .isoLatin1, charsetSentinel: true)
        let utf = DecodeOptions(charset: .utf8, charsetSentinel: true)
        let def = DecodeOptions(charsetSentinel: true)

        var r = try Qs.decode(
            "utf8=\(urlEncodedCheckmarkInUtf8)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)",
            options: iso)
        #expect(r["ø"] as? String == "ø")

        r = try Qs.decode(
            "utf8=\(urlEncodedNumCheckmark)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)",
            options: utf)
        #expect(r["Ã¸"] as? String == "Ã¸")

        r = try Qs.decode(
            "a=\(urlEncodedOSlashInUtf8)&utf8=\(urlEncodedNumCheckmark)", options: utf)
        #expect(r["a"] as? String == "Ã¸")

        r = try Qs.decode(
            "utf8=foo&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)", options: utf)
        #expect(r["ø"] as? String == "ø")

        r = try Qs.decode(
            "utf8=\(urlEncodedCheckmarkInUtf8)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)",
            options: def)
        #expect(r["ø"] as? String == "ø")

        r = try Qs.decode(
            "utf8=\(urlEncodedNumCheckmark)&\(urlEncodedOSlashInUtf8)=\(urlEncodedOSlashInUtf8)",
            options: def)
        #expect(r["Ã¸"] as? String == "Ã¸")
    }

    // MARK: - numeric entities

    @Test("parse: interpret numeric entities")
    func parse_numericEntities() throws {
        let urlEncodedNumSmiley = "%26%239786%3B"
        let iso = DecodeOptions(charset: .isoLatin1)
        let isoInterpret = DecodeOptions(charset: .isoLatin1, interpretNumericEntities: true)
        let utfInterpret = DecodeOptions(charset: .utf8, interpretNumericEntities: true)

        var r = try Qs.decode("foo=\(urlEncodedNumSmiley)", options: isoInterpret)
        #expect(r["foo"] as? String == "☺")

        r = try Qs.decode("foo=\(urlEncodedNumSmiley)", options: iso)
        #expect(r["foo"] as? String == "&#9786;")

        r = try Qs.decode("foo=\(urlEncodedNumSmiley)", options: utfInterpret)
        #expect(r["foo"] as? String == "&#9786;")
    }

    // MARK: - key/value decoder lowercasing

    @Test("parse: allow decoding keys and values")
    func parse_keyValueDecoder() throws {
        let dec: ScalarDecoder = { s, _, _ in s?.lowercased() }
        let opt = DecodeOptions(decoder: dec)

        let r = try Qs.decode("KeY=vAlUe", options: opt)
        #expect(r["key"] as? String == "value")
    }

    // MARK: - proof of concept

    @Test("parse: proof of concept")
    func parse_poc() throws {
        let r = try Qs.decode("filters[name][:eq]=John&filters[age][:ge]=18&filters[age][:le]=60")
        let filters = r["filters"] as? [String: Any]
        let name = filters?["name"] as? [String: Any]
        let age = filters?["age"] as? [String: Any]
        #expect(name?[":eq"] as? String == "John")
        #expect(age?[":ge"] as? String == "18")
        #expect(age?[":le"] as? String == "60")
    }

    // MARK: - Empty test cases

    @Test("decode: parses empty keys (skips empty-string keys)")
    func decode_parses_empty_keys_parametrized() throws {
        for (i, element) in emptyTestCases().enumerated() {
            let label = (element["input"] as? String) ?? "case \(i)"
            let input = element["input"] as! String
            let expected = element["noEmptyKeys"] as! [String: Any]

            // Decode
            let decodedAny = try Qs.decode(input)
            let decoded = decodedAny

            // Deep compare via NSDictionary bridging
            let equal = NSDictionary(dictionary: decoded).isEqual(to: expected)
            #expect(
                equal, "mismatch\nENCODED: \(label)\nDECODED: \(decoded)\nEXPECTED: \(expected)")
        }
    }

    // MARK: - Only objectify top-level list*fragments to {"0":..., "1":...}

    @Test("decode: '&' (or trailing &) does not create a 'nil' key")
    func decode_does_not_create_nil_key() throws {
        let r1 = try Qs.decode("&")
        #expect(r1.isEmpty)

        let r2 = try Qs.decode("_r=1&")
        #expect(r2.keys.sorted() == ["_r"])
        #expect(r2["_r"] as? String == "1")
    }

    @Test("decode: bracketed numeric top-level keys become string indices")
    func decode_bracketed_numeric_top_level_to_string_indices() throws {
        let r1 = try Qs.decode("[0]=a&[1]=b")
        #expect(NSDictionary(dictionary: r1).isEqual(to: ["0": "a", "1": "b"]))

        let r2 = try Qs.decode("%5B0%5D=a&%5B1%5D=b")
        #expect(NSDictionary(dictionary: r2).isEqual(to: ["0": "a", "1": "b"]))
    }
}

// MARK: - DecodeOptions.defaultDecode (Kotlin parity — behavior-level port)

@Suite("DecodeOptions.defaultDecode — key protections (behavioral parity)")
struct DecodeOptionsDefaultDecodeBehaviorTests {
    let charsets: [String.Encoding] = [.utf8, .isoLatin1]

    @Test("KEY maps %2E/%2e inside brackets to '.' when allowDots=true (UTF-8/ISO-8859-1)")
    func keyMapsEncodedDotInsideBrackets_allowDotsTrue() throws {
        for cs in charsets {
            let r1 = try Qs.decode("a[%2E]=x", options: .init(allowDots: true, charset: cs))
            #expect(((r1["a"] as? [String: Any])?["."] as? String) == "x")

            let r2 = try Qs.decode("a[%2e]=x", options: .init(allowDots: true, charset: cs))
            #expect(((r2["a"] as? [String: Any])?["."] as? String) == "x")
        }
    }

    @Test(
        "KEY maps %2E outside brackets to '.' when allowDots=true; independent of decodeDotInKeys (UTF-8/ISO)"
    )
    func keyMapsEncodedDotTopLevel_allowDotsTrue_independentOfDecodeDotInKeys() throws {
        for cs in charsets {
            var r = try Qs.decode(
                "a%2Eb=c",
                options: .init(allowDots: true, decodeDotInKeys: false, charset: cs))
            #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")

            r = try Qs.decode(
                "a%2Eb=c",
                options: .init(allowDots: true, decodeDotInKeys: true, charset: cs))
            #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
        }
    }

    @Test("non-KEY decodes %2E to '.' (control)")
    func valueDecodesEncodedDot() throws {
        for cs in charsets {
            let r = try Qs.decode("x=%2E", options: .init(charset: cs))
            #expect(r["x"] as? String == ".")
        }
    }

    @Test("KEY maps %2E/%2e inside brackets even when allowDots=false")
    func keyMapsEncodedDotInsideBrackets_allowDotsFalse() throws {
        for cs in charsets {
            let r1 = try Qs.decode("a[%2E]=x", options: .init(allowDots: false, charset: cs))
            #expect(((r1["a"] as? [String: Any])?["."] as? String) == "x")

            let r2 = try Qs.decode("a[%2e]=x", options: .init(allowDots: false, charset: cs))
            #expect(((r2["a"] as? [String: Any])?["."] as? String) == "x")
        }
    }

    @Test("KEY outside %2E decodes to '.' when allowDots=false (no protection outside brackets)")
    func keyTopLevelEncodedDot_allowDotsFalse() throws {
        for cs in charsets {
            let r = try Qs.decode("a%2Eb=c", options: .init(allowDots: false, charset: cs))
            #expect(r["a.b"] as? String == "c")
        }
    }
}

// MARK: - DecodeOptions interplay

@Suite("DecodeOptions: allowDots / decodeDotInKeys interplay")
struct DecodeOptionsInterplayParityTests {
    @Test(
        "decodeDotInKeys=true implies effective dot-splitting when allowDots is not explicitly false"
    )
    func decodeDotInKeysImpliesEffectiveAllowDots() throws {
        // When only decodeDotInKeys=true is provided, the implementation should behave as if top-level
        // dot-splitting were enabled.
        let r = try Qs.decode("a.b=c", options: .init(decodeDotInKeys: true))
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }
}

// MARK: - DecodeOptions key/value decoding + custom decoder behavior (C# parity)

@Suite("DecodeOptions: key/value decoding + custom decoder behavior")
struct DecodeOptionsCustomDecoderParity {

    @Test("kind-aware decoder receives KEY for top-level and bracketed keys")
    func kindAwareDecoderReceivesKey() throws {
        // Thread-safe, sendable sink that avoids capturing a non-sendable mutable array.
        final class CallSink: @unchecked Sendable {
            private var _items: [(String?, DecodeKind)] = []
            private let lock = NSLock()
            func add(_ s: String?, _ k: DecodeKind?) {
                lock.lock()
                defer { lock.unlock() }
                _items.append((s, k ?? .value))
            }
            var items: [(String?, DecodeKind)] {
                lock.lock()
                defer { lock.unlock() }
                return _items
            }
        }

        let sink = CallSink()

        let dec: ScalarDecoder = { s, _, k in
            sink.add(s, k)
            return s  // echo back
        }

        _ = try Qs.decode(
            "a%2Eb=c&a[b]=d",
            options: .init(allowDots: true, decoder: dec, decodeDotInKeys: true)
        )

        #expect(
            sink.items.contains {
                $0.1 == .key && ($0.0 == "a%2Eb" || $0.0 == "a[b]")
            })
        #expect(
            sink.items.contains {
                $0.1 == .value && ($0.0 == "c" || $0.0 == "d")
            })
    }

    @Test(
        "Single decoder acts like 'legacy' when ignoring kind (no default percent-decoding first)")
    func singleDecoderLegacyBehavior() throws {
        let dec: ScalarDecoder = { s, _, _ in s?.uppercased() }

        // Keys and values are fed raw to the decoder; no default percent-decoding first.
        var r = try Qs.decode("abc=def", options: .init(decoder: dec))
        #expect(r["ABC"] as? String == "DEF")

        // Encoded dot stays encoded because our custom decoder never percent-decodes.
        r = try Qs.decode("a%2Eb=z", options: .init(allowDots: false, decoder: dec))
        #expect(r["A%2EB"] as? String == "Z")
    }

    @Test("decoder wins over legacyDecoder when both are provided")
    func decoderWinsOverLegacyDecoder() throws {
        @available(*, deprecated) typealias Legacy = LegacyDecoder
        let legacy: Legacy = { v, _ in "L:\(v ?? "null")" }
        let dec: ScalarDecoder = { v, _, k in "K:\(k ?? .value):\(v ?? "null")" }
        let opt = DecodeOptions(decoder: dec, legacyDecoder: legacy)

        let r = try Qs.decode("x=y", options: opt)
        #expect(r["K:key:x"] as? String == "K:value:y")
    }

    @Test("decodeKey coerces non-string decoder result via String(describing:)")
    func decodeKeyCoercesToString() throws {
        let dec: ScalarDecoder = { _, _, k in
            if k == .key { return 42 } else { return "v" }
        }
        let r = try Qs.decode("anything=v", options: .init(decoder: dec))
        #expect(r["42"] as? String == "v")
    }

    // Note: The Kotlin test that asserts constructor-time validation throwing for
    // (allowDots=false, decodeDotInKeys=true) is not portable here because Swift enforces
    // it via a precondition (crash), not a throwable initializer. We already cover this
    // invalid combo in other suites by marking such tests disabled.
}

// MARK: - Encoded dot behavior in keys (%2E / %2e) — comprehensive coverage

@Suite("encoded dot behavior in keys (%2E / %2e)")
struct EncodedDotKeyBehaviorTests {

    @Test(
        "allowDots=false, decodeDotInKeys=false: encoded dots decode to literal '.'; no dot-splitting"
    )
    func encodedDot_noAllow_noDecodeDotKeys() throws {
        let opt = DecodeOptions(allowDots: false, decodeDotInKeys: false)

        var r = try Qs.decode("a%2Eb=c", options: opt)
        #expect(r["a.b"] as? String == "c")

        r = try Qs.decode("a%2eb=c", options: opt)
        #expect(r["a.b"] as? String == "c")
    }

    @Test(
        "allowDots=true, decodeDotInKeys=false: double-encoded dots are preserved inside segments; encoded and plain dots split"
    )
    func allowDots_true_decodeDotInKeys_false_behavior() throws {
        // Plain dot splits
        var r = try Qs.decode("a.b=c", options: .init(allowDots: true, decodeDotInKeys: false))
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")

        // Double-encoded dot stays encoded inside first segment (no extra split for that part)
        r = try Qs.decode(
            "name%252Eobj.first=John",
            options: .init(allowDots: true, decodeDotInKeys: false))
        let seg = r["name%2Eobj"] as? [String: Any]
        #expect((seg?["first"] as? String) == "John")

        // Lowercase single-encoded inside the *first* segment → upstream percent-decoding
        // exposes the '.'; allowDots splits: "a%2eb.c=d" → a → b → c
        r = try Qs.decode(
            "a%2eb.c=d",
            options: .init(allowDots: true, decodeDotInKeys: false))
        let a = r["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        #expect((b?["c"] as? String) == "d")
    }

    @Test(
        "allowDots=true, decodeDotInKeys=true: encoded dots become literal '.' inside a segment (no extra split)"
    )
    func allowDots_true_decodeDotInKeys_true_behavior() throws {
        var r = try Qs.decode(
            "name%252Eobj.first=John",
            options: .init(allowDots: true, decodeDotInKeys: true))
        #expect(((r["name.obj"] as? [String: Any])?["first"] as? String) == "John")

        // Double-encoded single segment becomes a literal dot
        r = try Qs.decode(
            "a%252Eb=c",
            options: .init(allowDots: true, decodeDotInKeys: true))
        #expect(r["a.b"] as? String == "c")

        // Lowercase variant inside brackets
        r = try Qs.decode(
            "a[%2e]=x",
            options: .init(allowDots: true, decodeDotInKeys: true))
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
    }

    @Test("bracket segment: %2E mapped based on decodeDotInKeys; case-insensitive")
    func bracketSegment_mapping_caseInsensitive() throws {
        // When disabled, keep '.' result (percent-decoding inside bracket) without further mapping
        var r = try Qs.decode(
            "a[%2E]=x",
            options: .init(allowDots: false, decodeDotInKeys: false))
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")

        r = try Qs.decode(
            "a[%2e]=x",
            options: .init(allowDots: true, decodeDotInKeys: false))
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")

        // When enabled, convert to '.' regardless of case
        r = try Qs.decode(
            "a[%2E]=x",
            options: .init(allowDots: true, decodeDotInKeys: true))
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
    }

    /// Invalid combination (decodeDotInKeys=true while allowDots=false) is enforced by a precondition
    /// in DecodeOptions init; cannot be caught here. See dedicated disabled test below.
    @Test(
        "allowDots=false, decodeDotInKeys=true is invalid (precondition in initializer)",
        .enabled(if: false, "initializer precondition; cannot be caught with #expect(throws:)")
    )
    func parity_invalidCombo_PRECONDITION() throws {
        _ = try Qs.decode(
            "a[%2e]=x",
            options: .init(allowDots: false, decodeDotInKeys: true)
        )
    }

    @Test("bare-key (no '='): behavior matches key decoding path")
    func bareKey_behavesLikeKeyDecoding() throws {
        // allowDots=false → %2E becomes '.'; no splitting; strictNullHandling → NSNull
        var r = try Qs.decode(
            "a%2Eb",
            options: .init(
                allowDots: false,
                decodeDotInKeys: false,
                strictNullHandling: true))
        #expect(r.keys.contains("a.b"))
        #expect((r["a.b"] is NSNull))

        // allowDots=true & decodeDotInKeys=false — upstream exposes '.'; split on dot; empty value
        r = try Qs.decode(
            "a%2Eb",
            options: .init(allowDots: true, decodeDotInKeys: false))
        let a = r["a"] as? [String: Any]
        #expect((a?["b"] as? String) == "")
    }

    @Test("depth=0 with allowDots=true: do not split key")
    func depthZero_disablesTopLevelDotSplitting() throws {
        let r = try Qs.decode("a.b=c", options: .init(allowDots: true, depth: 0))
        #expect(r["a.b"] as? String == "c")
    }

    @Test("top-level dot→bracket conversion guardrails: leading/trailing/double dots")
    func dotToBracket_guardrails() throws {
        // Leading dot: ".a" → { "a": "x" } (when allowDots=true)
        var r = try Qs.decode(".a=x", options: .init(allowDots: true, decodeDotInKeys: false))
        #expect(((r["a"] as? String) == "x"))

        // Trailing dot: "a." remains literal
        r = try Qs.decode("a.=x", options: .init(allowDots: true, decodeDotInKeys: false))
        #expect(r["a."] as? String == "x")

        // Double dots: only the second dot (before a token) causes a split; middle dot is literal
        r = try Qs.decode("a..b=x", options: .init(allowDots: true, decodeDotInKeys: false))
        let a = r["a."] as? [String: Any]
        #expect((a?["b"] as? String) == "x")
    }

    // --- C# parity subset (top-level + bracket + charset) ---

    @Test(
        "top-level: allowDots=true, decodeDotInKeys=true → plain & encoded dots split (upper/lower)"
    )
    func parity_topLevel_allowDots_decodeDotInKeys_true() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true)

        var r = try Qs.decode("a.b=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")

        r = try Qs.decode("a%2Eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")

        r = try Qs.decode("a%2eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }

    @Test(
        "top-level: allowDots=true, decodeDotInKeys=false → encoded dot also splits (upper/lower)")
    func parity_topLevel_allowDots_true_decodeDotInKeys_false() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: false)

        var r = try Qs.decode("a%2Eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")

        r = try Qs.decode("a%2eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }

    // NOTE: intentionally disabled — this combination violates a precondition in the initializer
    @Test(
        "allowDots=false, decodeDotInKeys=true is invalid",
        .enabled(if: false, "initializer precondition; cannot be caught with #expect(throws:)")
    )
    func parity_invalidCombo() throws {
        _ = try Qs.decode(
            "a%2Eb=c",
            options: .init(allowDots: false, decodeDotInKeys: true)
        )
    }

    @Test("bracket segment: maps to '.' when decodeDotInKeys=true (case-insensitive)")
    func parity_bracket_mapsToDot_whenDecodeDotInKeysTrue() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true)
        var r = try Qs.decode("a[%2E]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
        r = try Qs.decode("a[%2e]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
    }

    @Test(
        "bracket segment: when decodeDotInKeys=false, percent-decoding inside brackets yields '.' (case-insensitive)"
    )
    func parity_bracket_percentDecoding_whenDecodeDotInKeysFalse() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: false)
        var r = try Qs.decode("a[%2E]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
        r = try Qs.decode("a[%2e]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
    }

    @Test("value tokens always decode %2E → '.'")
    func parity_valueTokens_decode_percentDot() throws {
        let r = try Qs.decode("x=%2E")
        #expect(r["x"] as? String == ".")
    }

    @Test("latin1: allowDots=true, decodeDotInKeys=true behaves like UTF-8 for top-level & bracket")
    func parity_latin1_allowDots_true_decodeDotInKeys_true() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true, charset: .isoLatin1)
        var r = try Qs.decode("a%2Eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
        r = try Qs.decode("a[%2E]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
    }

    @Test(
        "latin1: allowDots=true, decodeDotInKeys=false also splits top-level and decodes inside brackets"
    )
    func parity_latin1_allowDots_true_decodeDotInKeys_false() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: false, charset: .isoLatin1)
        var r = try Qs.decode("a%2Eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
        r = try Qs.decode("a[%2E]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["."] as? String) == "x")
    }

    @Test(
        "mixed-case encoded brackets + encoded dot after brackets (allowDots=true, decodeDotInKeys=true)"
    )
    func parity_mixedCase_encodedBrackets_plus_encodedDot_after() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true)
        var r = try Qs.decode("a%5Bb%5D%5Bc%5D%2Ed=x", options: opt)
        #expect(
            (((r["a"] as? [String: Any])?["b"] as? [String: Any])?["c"] as? [String: Any])?["d"]
                as? String == "x")
        r = try Qs.decode("a%5bb%5d%5bc%5d%2ed=x", options: opt)
        #expect(
            (((r["a"] as? [String: Any])?["b"] as? [String: Any])?["c"] as? [String: Any])?["d"]
                as? String == "x")
    }

    @Test("nested brackets inside a bracket segment (balanced as one segment)")
    func parity_nestedBrackets_insideSegment() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true)
        // "a[b%5Bc%5D].e=x" → key "b[c]" stays one segment; then ".e" splits
        let r = try Qs.decode("a[b%5Bc%5D].e=x", options: opt)
        let a = r["a"] as? [String: Any]
        #expect(((a?["b[c]"] as? [String: Any])?["e"] as? String) == "x")
    }

    // NOTE: intentionally disabled — this combination violates a precondition in the initializer
    @Test(
        "mixed-case encoded brackets + encoded dot with allowDots=false & decodeDotInKeys=true throws",
        .enabled(if: false, "initializer precondition; cannot be caught with #expect(throws:)")
    )
    func parity_mixedCase_invalidCombo_throws() throws {
        _ = try Qs.decode(
            "a%5Bb%5D%5Bc%5D%2Ed=x",
            options: .init(allowDots: false, decodeDotInKeys: true)
        )
    }

    @Test("bracket then encoded dot to next segment with allowDots=true")
    func parity_bracket_then_encodedDot_nextSegment() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true)
        var r = try Qs.decode("a[b]%2Ec=x", options: opt)
        #expect((((r["a"] as? [String: Any])?["b"] as? [String: Any])?["c"] as? String) == "x")
        r = try Qs.decode("a[b]%2ec=x", options: opt)
        #expect((((r["a"] as? [String: Any])?["b"] as? [String: Any])?["c"] as? String) == "x")
    }

    @Test("mixed-case: top-level encoded dot then bracket with allowDots=true")
    func parity_topLevel_encodedDot_then_bracket() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: true)
        let r = try Qs.decode("a%2E[b]=x", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "x")
    }

    @Test("top-level lowercase encoded dot splits when allowDots=true (decodeDotInKeys=false)")
    func parity_lowercaseEncodedDot_allowDots_true_decodeDotInKeys_false() throws {
        let opt = DecodeOptions(allowDots: true, decodeDotInKeys: false)
        let r = try Qs.decode("a%2eb=c", options: opt)
        #expect(((r["a"] as? [String: Any])?["b"] as? String) == "c")
    }

    @Test("dot before index with allowDots=true: index remains index")
    func parity_dotBeforeIndex_allowDots_true() throws {
        let opt = DecodeOptions(allowDots: true)
        let r = try Qs.decode("foo[0].baz[0]=15&foo[0].bar=2", options: opt)
        let foo = r["foo"] as? [Any]
        let zero = foo?.first as? [String: Any]
        #expect((zero?["bar"] as? String) == "2")
        #expect((zero?["baz"] as? [String]) == ["15"])
    }

    @Test("trailing dot ignored when allowDots=true")
    func parity_trailingDot_ignored_allowDots_true() throws {
        let r = try Qs.decode("user.email.=x", options: .init(allowDots: true))
        #expect(((r["user"] as? [String: Any])?["email"] as? String) == "x")
    }

    // NOTE: The Kotlin test "kind-aware decoder receives KEY ..." is omitted here:
    // Swift's ValueDecoder currently has the signature (String?, String.Encoding?) -> Any?
    // and does not receive a DecodeKind. Once you add a kind-aware hook, you can port that test.
}

// MARK: - Remainder wrapping & strictDepth behavior (ported expectations)

@Suite("splitKeyIntoSegments — remainder wrapping & strictDepth behavior")
struct RemainderWrappingStrictDepthTests {

    @Test(
        "allowDots=true, depth=1: wrap the remainder from the next unprocessed bracket"
    )
    func remainderWrapped_allowDots_depth1() throws {
        let segs = try QsSwift.Decoder.splitKeyIntoSegments(
            originalKey: "a.b.c",
            allowDots: true,
            maxDepth: 1,
            strictDepth: false
        )
        #expect(segs == ["a", "[b]", "[[c]]"])  // Kotlin: ["a","[b]","[[c]]"]
    }

    @Test(
        "bracketed input, depth=2: collect two groups, wrap remainder as a single synthetic segment"
    )
    func remainderWrapped_bracketed_depth2() throws {
        let segs = try QsSwift.Decoder.splitKeyIntoSegments(
            originalKey: "a[b][c][d]",
            allowDots: false,
            maxDepth: 2,
            strictDepth: false
        )
        #expect(segs == ["a", "[b]", "[c]", "[[d]]"])  // Kotlin: ["a","[b]","[c]","[[d]]"]
    }

    @Test(
        "unterminated bracket group: do not throw even with strictDepth=true; wrap raw remainder"
    )
    func unterminatedBracket_noThrowStrict() throws {
        // Unterminated after first '[': "a[b[c" -> ["a", "[[b[c]"]
        let segs = try QsSwift.Decoder.splitKeyIntoSegments(
            originalKey: "a[b[c",
            allowDots: false,
            maxDepth: 5,
            strictDepth: true
        )
        #expect(segs == ["a", "[[b[c]"])
    }

    @Test("strictDepth=true: well-formed depth overflow throws")
    func wellFormedDepthOverflow_throws() {
        var didThrow = false
        do {
            _ = try QsSwift.Decoder.splitKeyIntoSegments(
                originalKey: "a[b][c][d]",
                allowDots: false,
                maxDepth: 2,
                strictDepth: true
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("depth=0: never split; return the original key as a single segment")
    func depthZero_neverSplit() throws {
        var segs = try QsSwift.Decoder.splitKeyIntoSegments(
            originalKey: "a.b.c",
            allowDots: true,
            maxDepth: 0,
            strictDepth: false
        )
        #expect(segs == ["a.b.c"])  // depth=0: never split

        segs = try QsSwift.Decoder.splitKeyIntoSegments(
            originalKey: "a[b][c]",
            allowDots: false,
            maxDepth: 0,
            strictDepth: false
        )
        #expect(segs == ["a[b][c]"])  // depth=0: never split
    }
}

// MARK: - Helpers

private func unwrapOptional(_ any: Any) -> Any? {
    let m = Mirror(reflecting: any)
    guard m.displayStyle == .optional else { return any }
    return m.children.first?.value
}

private func as2DStrings(_ value: Any?) -> [[String]]? {
    guard let outer = value as? [Any] else { return nil }
    var out: [[String]] = []
    out.reserveCapacity(outer.count)
    for innerAny in outer {
        guard let inner = innerAny as? [Any] else { return nil }
        let row = inner.compactMap { unwrapOptional($0) as? String }
        out.append(row)
    }
    return out
}

private func isNSNull(_ v: Any??) -> Bool {
    switch v {
    case .some(.some(_ as NSNull)): return true
    default: return false
    }
}

@Test("parseQueryStringValues throws when parameter limit exceeded")
func parseQuery_enforcesParameterLimit() {
    let options = DecodeOptions(parameterLimit: 1, throwOnLimitExceeded: true)
    #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
        _ = try Decoder.parseQueryStringValues("a=1&b=2", options: options)
    }
}

@Test("parseQueryStringValues honors charset sentinel")
func parseQuery_honorsCharsetSentinel() throws {
    let options = DecodeOptions(charsetSentinel: true)
    let out = try Decoder.parseQueryStringValues(
        "utf8=%E2%9C%93&value=%E4%B8%AD",
        options: options
    )
    #expect(out["value"] as? String == "中")
}

@Test("parseQueryStringValues uses custom scalar decoder")
func parseQuery_usesCustomDecoder() throws {
    let options = DecodeOptions(decoder: { value, _, _ in value?.uppercased() })
    let out = try Decoder.parseQueryStringValues("key=value", options: options)
    #expect(out["KEY"] as? String == "VALUE")
}

@Test("parseQueryStringValues interprets numeric entities in latin1 mode")
func parseQuery_interpretsNumericEntities() throws {
    let options = DecodeOptions(charset: .isoLatin1, interpretNumericEntities: true)
    let out = try Decoder.parseQueryStringValues("value=%26%239786%3B", options: options)
    #expect(out["value"] as? String == "☺")
}

private func isNSNullValue(_ v: Any?) -> Bool { v is NSNull }

private func asStrings(_ v: Any?) -> [String]? {
    (v as? [Any])?.compactMap { $0 as? String }
}

private func flatStrings(_ v: Any?) -> [String]? {
    (v as? [Any])?.compactMap { ($0 as AnyObject) as? String }
}

private func asDictAnyHashable(_ v: Any?) -> [AnyHashable: Any]? { v as? [AnyHashable: Any] }

private func asDictString(_ v: Any?) -> [String: Any]? {
    v as? [String: Any]
}

private func envFlag(_ name: String) -> Bool? {
    guard let v = ProcessInfo.processInfo.environment[name] else { return nil }
    return ["1", "true", "yes", "y", "on"].contains(v.lowercased())
}

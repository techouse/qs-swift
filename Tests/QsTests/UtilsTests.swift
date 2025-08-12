import Foundation
@_spi(Testing) @testable import Qs

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct UtilsTests {
    // MARK: - Utils.encode tests

    @Test("Utils.encode - encodes various values correctly")
    func testEncodeVariousValues() async throws {
        // Basic encoding
        #expect(Utils.encode("foo+bar") == "foo%2Bbar")

        // Exceptions (characters that should not be encoded)
        #expect(Utils.encode("foo-bar") == "foo-bar")
        #expect(Utils.encode("foo_bar") == "foo_bar")
        #expect(Utils.encode("foo~bar") == "foo~bar")
        #expect(Utils.encode("foo.bar") == "foo.bar")

        // Space encoding
        #expect(Utils.encode("foo bar") == "foo%20bar")

        // Parentheses
        #expect(Utils.encode("foo(bar)") == "foo%28bar%29")
        #expect(Utils.encode("foo(bar)", format: .rfc1738) == "foo(bar)")

        // Enum encoding
        #expect(Utils.encode(DummyEnum.lorem) == "LOREM")

        // Values that should not be encoded (return empty string)
        // Array
        #expect(Utils.encode([1, 2]) == "")
        // Dictionary
        #expect(Utils.encode(["a": "b"]) == "")
        // Undefined
        #expect(Utils.encode(Undefined()) == "")
    }

    @Test("Utils.encode - encode huge string")
    func testEncodeHugeString() async throws {
        let hugeString = String(repeating: "a", count: 1_000_000)
        #expect(Utils.encode(hugeString) == hugeString)
    }

    @Test("Utils.encode - encodes utf8")
    func testEncodeUtf8() async throws {
        #expect(Utils.encode("foo+bar", charset: .utf8) == "foo%2Bbar")
        // exceptions
        #expect(Utils.encode("foo-bar", charset: .utf8) == "foo-bar")
        #expect(Utils.encode("foo_bar", charset: .utf8) == "foo_bar")
        #expect(Utils.encode("foo~bar", charset: .utf8) == "foo~bar")
        #expect(Utils.encode("foo.bar", charset: .utf8) == "foo.bar")
        // space
        #expect(Utils.encode("foo bar", charset: .utf8) == "foo%20bar")
        // parentheses
        #expect(Utils.encode("foo(bar)", charset: .utf8) == "foo%28bar%29")
        #expect(Utils.encode("foo(bar)", charset: .utf8, format: .rfc1738) == "foo(bar)")
    }

    @Test("Utils.encode - encodes latin1")
    func testEncodeLatin1() async throws {
        #expect(Utils.encode("foo+bar", charset: .isoLatin1) == "foo+bar")
        // exceptions
        #expect(Utils.encode("foo-bar", charset: .isoLatin1) == "foo-bar")
        #expect(Utils.encode("foo_bar", charset: .isoLatin1) == "foo_bar")
        #expect(Utils.encode("foo~bar", charset: .isoLatin1) == "foo%7Ebar")
        #expect(Utils.encode("foo.bar", charset: .isoLatin1) == "foo.bar")
        // space
        #expect(Utils.encode("foo bar", charset: .isoLatin1) == "foo%20bar")
        // parentheses
        #expect(Utils.encode("foo(bar)", charset: .isoLatin1) == "foo%28bar%29")
        #expect(Utils.encode("foo(bar)", charset: .isoLatin1, format: .rfc1738) == "foo(bar)")
    }

    @Test("Utils.encode - encodes empty string")
    func testEncodeEmptyString() async throws {
        #expect(Utils.encode("") == "")
    }

    @Test("Utils.encode - encodes parentheses with default format")
    func testEncodeParenthesesDefaultFormat() async throws {
        #expect(Utils.encode("(abc)") == "%28abc%29")
    }

    @Test("Utils.encode - encodes unicode with ISO-8859-1 charset")
    func testEncodeUnicodeIso88591() async throws {
        #expect(
            Utils.encode("abc 123 💩", charset: .isoLatin1)
                == "abc%20123%20%26%2355357%3B%26%2356489%3B")
    }

    @Test("Utils.encode - encodes unicode with UTF-8 charset")
    func testEncodeUnicodeUtf8() async throws {
        #expect(Utils.encode("abc 123 💩") == "abc%20123%20%F0%9F%92%A9")
    }

    @Test("Utils.encode - encodes long strings efficiently")
    func testEncodeLongStrings() async throws {
        let longString = String(repeating: " ", count: 1500)
        let expectedString = String(repeating: "%20", count: 1500)
        #expect(Utils.encode(longString) == expectedString)
    }

    @Test("Utils.encode - encodes parentheses")
    func testEncodeParentheses() async throws {
        #expect(Utils.encode("()") == "%28%29")
        #expect(Utils.encode("()", format: .rfc1738) == "()")
    }

    @Test("Utils.encode - encodes multi-byte unicode characters")
    func testEncodeMultiByteUnicode() async throws {
        #expect(Utils.encode("Āက豈") == "%C4%80%E1%80%80%EF%A4%80")
    }

    @Test("Utils.encode - encodes surrogate pairs")
    func testEncodeSurrogatePairs() async throws {
        #expect(Utils.encode("\u{1F4A9}") == "%F0%9F%92%A9")
        #expect(Utils.encode("💩") == "%F0%9F%92%A9")
    }

    @Test("Utils.encode - encodes emoji with ISO-8859-1 charset")
    func testEncodeEmojiIso88591() async throws {
        #expect(Utils.encode("💩", charset: .isoLatin1) == "%26%2355357%3B%26%2356489%3B")
    }

    @Test("Utils.encode - encodes nil values")
    func testEncodeNilValues() async throws {
        #expect(Utils.encode(nil) == "")
    }

    @Test("Utils.encode - encodes byte arrays")
    func testEncodeByteArrays() async throws {
        let data = "test".data(using: .utf8)!
        #expect(Utils.encode(data) == "test")
    }

    @Test("Utils.encode - returns empty string for unsupported types")
    func testEncodeUnsupportedTypes() async throws {
        #expect(Utils.encode([1, 2, 3]) == "")
        #expect(Utils.encode(["a": "b"]) == "")
        #expect(Utils.encode(Undefined()) == "")
    }

    @Test("Utils.encode - handles special characters")
    func testEncodeSpecialCharacters() async throws {
        #expect(Utils.encode("~._-") == "~._-")
        #expect(Utils.encode("!@#$%^&*()") == "%21%40%23%24%25%5E%26%2A%28%29")
    }

    @Test("Utils.encode - latin1 encodes characters as numeric entities when not representable")
    func testEncodeLatin1NumericEntities() async throws {
        let out = Utils.encode("☺", charset: .isoLatin1, format: .rfc3986)
        #expect(out == "%26%239786%3B")
    }

    @Test("Utils.encode - RFC1738 leaves parentheses unescaped")
    func testEncodeRfc1738Parentheses() async throws {
        let out = Utils.encode("()", charset: .utf8, format: .rfc1738)
        #expect(out == "()")
    }

    @Test("Utils.encode - encodes surrogate pairs (emoji) correctly")
    func testEncodeSurrogatePairsEmoji() async throws {
        #expect(Utils.encode("😀") == "%F0%9F%98%80")
    }

    @Test("Utils.encode - encodes Data")
    func testEncodeData() async throws {
        let data = "ä".data(using: .utf8)!
        #expect(Utils.encode(data) == "%C3%A4")

        let hiData = "hi".data(using: .utf8)!
        #expect(Utils.encode(hiData) == "hi")
    }

    // MARK: - Utils.decode tests

    @Test("Utils.decode - decodes URL encoded strings")
    func testDecodeUrlEncodedStrings() async throws {
        #expect(Utils.decode("foo%2Bbar") == "foo+bar")
    }

    @Test("Utils.decode - handles exceptions (characters that don't need decoding)")
    func testDecodeExceptions() async throws {
        #expect(Utils.decode("foo-bar") == "foo-bar")
        #expect(Utils.decode("foo_bar") == "foo_bar")
        #expect(Utils.decode("foo~bar") == "foo~bar")
        #expect(Utils.decode("foo.bar") == "foo.bar")
    }

    @Test("Utils.decode - decodes spaces")
    func testDecodeSpaces() async throws {
        #expect(Utils.decode("foo%20bar") == "foo bar")
    }

    @Test("Utils.decode - decodes parentheses")
    func testDecodeParentheses() async throws {
        #expect(Utils.decode("foo%28bar%29") == "foo(bar)")
    }

    @Test("Utils.decode - decodes utf8")
    func testDecodeUtf8() async throws {
        #expect(Utils.decode("foo%2Bbar", charset: .utf8) == "foo+bar")
        // exceptions
        #expect(Utils.decode("foo-bar", charset: .utf8) == "foo-bar")
        #expect(Utils.decode("foo_bar", charset: .utf8) == "foo_bar")
        #expect(Utils.decode("foo~bar", charset: .utf8) == "foo~bar")
        #expect(Utils.decode("foo.bar", charset: .utf8) == "foo.bar")
        // space
        #expect(Utils.decode("foo%20bar", charset: .utf8) == "foo bar")
        // parentheses
        #expect(Utils.decode("foo%28bar%29", charset: .utf8) == "foo(bar)")
    }

    @Test("Utils.decode - decode latin1")
    func testDecodeLatin1() async throws {
        #expect(Utils.decode("foo+bar", charset: .isoLatin1) == "foo bar")
        // exceptions
        #expect(Utils.decode("foo-bar", charset: .isoLatin1) == "foo-bar")
        #expect(Utils.decode("foo_bar", charset: .isoLatin1) == "foo_bar")
        #expect(Utils.decode("foo%7Ebar", charset: .isoLatin1) == "foo~bar")
        #expect(Utils.decode("foo.bar", charset: .isoLatin1) == "foo.bar")
        // space
        #expect(Utils.decode("foo%20bar", charset: .isoLatin1) == "foo bar")
        // parentheses
        #expect(Utils.decode("foo%28bar%29", charset: .isoLatin1) == "foo(bar)")
    }

    @Test("Utils.decode - decodes URL-encoded strings")
    func testDecodeUrlEncodedStrings2() async throws {
        #expect(Utils.decode("a+b") == "a b")
        #expect(Utils.decode("name%2Eobj") == "name.obj")
        #expect(Utils.decode("name%2Eobj%2Efoo", charset: .isoLatin1) == "name.obj.foo")
    }

    // MARK: - Utils.escape tests

    @Test("Utils.escape - handles basic alphanumerics (remain unchanged)")
    func testEscapeBasicAlphanumerics() async throws {
        #expect(
            Utils.escape("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./")
                == "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./")
        #expect(Utils.escape("abc123") == "abc123")
    }

    @Test("Utils.escape - handles accented characters (Latin-1 range uses %XX)")
    func testEscapeAccentedCharacters() async throws {
        #expect(Utils.escape("äöü") == "%E4%F6%FC")
    }

    @Test("Utils.escape - handles non-ASCII that falls outside Latin-1 uses %uXXXX")
    func testEscapeNonAsciiOutsideLatin1() async throws {
        #expect(Utils.escape("ć") == "%u0107")
    }

    @Test("Utils.escape - handles characters that are defined as safe")
    func testEscapeSafeCharacters() async throws {
        #expect(Utils.escape("@*_+-./") == "@*_+-./")
    }

    @Test("Utils.escape - handles parentheses (in RFC3986 they are encoded)")
    func testEscapeParenthesesRfc3986() async throws {
        #expect(Utils.escape("(") == "%28")
        #expect(Utils.escape(")") == "%29")
    }

    @Test("Utils.escape - handles space character")
    func testEscapeSpaceCharacter() async throws {
        #expect(Utils.escape(" ") == "%20")
    }

    @Test("Utils.escape - handles tilde as safe")
    func testEscapeTildeAsSafe() async throws {
        #expect(Utils.escape("~") == "%7E")
    }

    @Test("Utils.escape - handles unsafe punctuation")
    func testEscapeUnsafePunctuation() async throws {
        #expect(Utils.escape("!") == "%21")
        #expect(Utils.escape(",") == "%2C")
    }

    @Test("Utils.escape - handles mixed safe and unsafe characters")
    func testEscapeMixedSafeUnsafe() async throws {
        #expect(Utils.escape("hello world!") == "hello%20world%21")
    }

    @Test("Utils.escape - handles multiple spaces")
    func testEscapeMultipleSpaces() async throws {
        #expect(Utils.escape("a b c") == "a%20b%20c")
    }

    @Test("Utils.escape - handles string with various punctuation")
    func testEscapeVariousPunctuation() async throws {
        #expect(Utils.escape("Hello, World!") == "Hello%2C%20World%21")
    }

    @Test("Utils.escape - handles null character")
    func testEscapeNullCharacter() async throws {
        #expect(Utils.escape("\u{0000}") == "%00")
    }

    @Test("Utils.escape - handles emoji")
    func testEscapeEmoji() async throws {
        #expect(Utils.escape("😀") == "%uD83D%uDE00")
    }

    @Test("Utils.escape - handles RFC1738 format where parentheses are safe")
    func testEscapeRfc1738Parentheses() async throws {
        #expect(Utils.escape("(", format: .rfc1738) == "(")
        #expect(Utils.escape(")", format: .rfc1738) == ")")
    }

    @Test("Utils.escape - handles mixed test with RFC1738")
    func testEscapeMixedRfc1738() async throws {
        #expect(Utils.escape("(hello)!", format: .rfc1738) == "(hello)%21")
    }

    @Test("Utils.escape - escape huge string")
    func testEscapeHugeString() async throws {
        let hugeString = String(repeating: "äöü", count: 1_000_000)
        let expectedString = String(repeating: "%E4%F6%FC", count: 1_000_000)
        #expect(Utils.escape(hugeString) == expectedString)
    }

    // MARK: - Utils.unescape tests

    @Test("Utils.unescape - No escapes")
    func testUnescapeNoEscapes() async throws {
        #expect(Utils.unescape("abc123") == "abc123")
    }

    @Test("Utils.unescape - Hex escapes with uppercase hex digits")
    func testUnescapeHexUppercase() async throws {
        #expect(Utils.unescape("%E4%F6%FC") == "äöü")
    }

    @Test("Utils.unescape - Hex escapes with lowercase hex digits")
    func testUnescapeHexLowercase() async throws {
        #expect(Utils.unescape("%e4%f6%fc") == "äöü")
    }

    @Test("Utils.unescape - Unicode escape")
    func testUnescapeUnicode() async throws {
        #expect(Utils.unescape("%u0107") == "ć")
    }

    @Test("Utils.unescape - Unicode escape with lowercase digits")
    func testUnescapeUnicodeLowercase() async throws {
        #expect(Utils.unescape("%u0061") == "a")
    }

    @Test("Utils.unescape - Characters that do not need escaping")
    func testUnescapeNoEscapingNeeded() async throws {
        #expect(Utils.unescape("@*_+-./") == "@*_+-./")
    }

    @Test("Utils.unescape - Hex escapes for punctuation")
    func testUnescapeHexPunctuation() async throws {
        #expect(Utils.unescape("%28") == "(")
        #expect(Utils.unescape("%29") == ")")
        #expect(Utils.unescape("%20") == " ")
        #expect(Utils.unescape("%7E") == "~")
    }

    @Test("Utils.unescape - A long string with only safe characters")
    func testUnescapeLongSafeString() async throws {
        #expect(
            Utils.unescape("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./")
                == "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./")
    }

    @Test("Utils.unescape - A mix of Unicode and hex escapes")
    func testUnescapeMixedUnicodeHex() async throws {
        #expect(Utils.unescape("%u0041%20%42") == "A B")
    }

    @Test("Utils.unescape - A mix of literal text and hex escapes")
    func testUnescapeMixedLiteralHex() async throws {
        #expect(Utils.unescape("hello%20world") == "hello world")
    }

    @Test(
        "Utils.unescape - A literal percent sign that is not followed by a valid escape remains unchanged"
    )
    func testUnescapeLiteralPercent() async throws {
        #expect(Utils.unescape("100% sure") == "100% sure")
    }

    @Test("Utils.unescape - Mixed Unicode and hex escapes")
    func testUnescapeMixedUnicodeHex2() async throws {
        #expect(Utils.unescape("%u0041%65") == "Ae")
    }

    @Test("Utils.unescape - Escaped percent signs that do not form a valid escape remain unchanged")
    func testUnescapeInvalidEscapePercent() async throws {
        #expect(Utils.unescape("50%% off") == "50%% off")
    }

    @Test("Utils.unescape - Consecutive escapes producing multiple spaces")
    func testUnescapeConsecutiveEscapes() async throws {
        #expect(Utils.unescape("%20%u0020") == "  ")
    }

    @Test("Utils.unescape - An invalid escape sequence should remain unchanged")
    func testUnescapeInvalidEscapeSequence() async throws {
        #expect(Utils.unescape("abc%g") == "abc%g")
    }

    @Test("Utils.unescape - An invalid Unicode escape sequence should remain unchanged")
    func testUnescapeInvalidUnicodeEscape() async throws {
        #expect(Utils.unescape("%uZZZZ") == "%uZZZZ")
        #expect(Utils.unescape("%u12") == "%u12")
        #expect(Utils.unescape("abc%") == "abc%")
    }

    @Test("Utils.unescape - huge string")
    func testUnescapeHugeString() async throws {
        let hugeString = String(repeating: "%E4%F6%FC", count: 1_000_000)
        let expectedString = String(repeating: "äöü", count: 1_000_000)
        #expect(Utils.unescape(hugeString) == expectedString)
    }

    @Test("Utils.unescape - leaves trailing '%' literal when incomplete escape")
    func testUnescapeTrailingPercent() async throws {
        #expect(Utils.unescape("%") == "%")
    }

    @Test("Utils.unescape - leaves incomplete %uXXXX literal")
    func testUnescapeIncompleteUnicode() async throws {
        #expect(Utils.unescape("%u12") == "%u12")
    }

    @Test("Utils.unescape - handles bad hex after %")
    func testUnescapeBadHex() async throws {
        #expect(Utils.unescape("%GZ") == "%GZ")
    }

    // MARK: - Utils.merge tests

    @Test("Utils.merge - merges Map with List")
    func testMergeMapWithList() async throws {
        let result = Utils.merge(target: [0: "a"], source: [Undefined(), "b"])
        let expected: [AnyHashable: Any] = [0: "a", 1: "b"]
        #expect(NSDictionary(dictionary: result as! [AnyHashable: Any]).isEqual(to: expected))
    }

    @Test("Utils.merge - merges two objects with the same key and different values")
    func testMergeTwoObjectsSameKeyDifferentValues() async throws {
        let target = ["foo": [["a": "a", "b": "b"], ["a": "aa"]]]
        let source = ["foo": [Undefined(), ["b": "bb"]]]
        let result = Utils.merge(target: target, source: source)
        let expected = ["foo": [["a": "a", "b": "b"], ["a": "aa", "b": "bb"]]]

        // Deep comparison needed for nested structures
        let resultDict = result as! [String: Any]
        let expectedDict = expected as [String: Any]
        #expect(resultDict.keys == expectedDict.keys)
    }

    @Test("Utils.merge - merges two objects with the same key and different list values")
    func testMergeTwoObjectsSameKeyDifferentListValues() async throws {
        let target = ["foo": [["baz": ["15"]]]]
        let source = ["foo": [["baz": [Undefined(), "16"]]]]
        let result = Utils.merge(target: target, source: source)
        let expected = ["foo": [["baz": ["15", "16"]]]]

        let resultDict = result as! [String: Any]
        let expectedDict = expected as [String: Any]
        #expect(resultDict.keys == expectedDict.keys)
    }

    @Test("Utils.merge - merges two objects with the same key and different values into a list")
    func testMergeTwoObjectsSameKeyIntoList() async throws {
        let target = ["foo": [["a": "b"]]]
        let source = ["foo": [["c": "d"]]]
        let result = Utils.merge(target: target, source: source)
        let expected = ["foo": [["a": "b", "c": "d"]]]

        let resultDict = result as! [String: Any]
        let expectedDict = expected as [String: Any]
        #expect(resultDict.keys == expectedDict.keys)
    }

    @Test("Utils.merge - merges true into null")
    func testMergeTrueIntoNull() async throws {
        let result = Utils.merge(target: nil, source: true)
        let resultArray = result as! [Any?]
        #expect(resultArray.count == 2)
        #expect(resultArray[0] == nil)
        #expect(resultArray[1] as! Bool == true)
    }

    @Test("Utils.merge - merges null into a list")
    func testMergeNullIntoList() async throws {
        let result = Utils.merge(target: nil, source: [42])
        let resultArray = result as! [Any?]
        #expect(resultArray.count == 2)
        #expect(resultArray[0] == nil)
        #expect(resultArray[1] as! Int == 42)
    }

    @Test("Utils.merge - merges null into a set")
    func testMergeNullIntoSet() async throws {
        let result = Utils.merge(target: nil, source: Set(["foo"]))
        let resultArray = result as! [Any?]
        #expect(resultArray.count == 2)
        #expect(resultArray[0] == nil)
        #expect(resultArray[1] as! String == "foo")
    }

    @Test("Utils.merge - merges String into set")
    func testMergeStringIntoSet() async throws {
        let result = Utils.merge(target: Set(["foo"]), source: "bar")
        let resultSet = result as! Set<AnyHashable>
        #expect(resultSet.contains("foo"))
        #expect(resultSet.contains("bar"))
        #expect(resultSet.count == 2)
    }

    @Test("Utils.merge - merges two objects with the same key")
    func testMergeTwoObjectsSameKey() async throws {
        let result = Utils.merge(target: ["a": "b"], source: ["a": "c"])
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("a"))

        let valueArray = resultDict["a"] as! [String]
        #expect(valueArray.contains("b"))
        #expect(valueArray.contains("c"))
    }

    @Test("Utils.merge - merges a standalone and an object into a list")
    func testMergeStandaloneAndObjectIntoList() async throws {
        let target = ["foo": "bar"]
        let source = ["foo": ["first": "123"]]
        let result = Utils.merge(target: target, source: source)
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))

        let valueArray = resultDict["foo"] as! [Any]
        #expect(valueArray.count == 2)
    }

    @Test("Utils.merge - merges a standalone and two objects into a list")
    func testMergeStandaloneAndTwoObjectsIntoList() async throws {
        let target = ["foo": ["bar", ["first": "123"]]]
        let source = ["foo": ["second": "456"]]
        let result = Utils.merge(target: target, source: source)
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))
    }

    @Test("Utils.merge - merges an object sandwiched by two standalones into a list")
    func testMergeObjectSandwichedByStandalones() async throws {
        let target = ["foo": ["bar", ["first": "123", "second": "456"]]]
        let source = ["foo": "baz"]
        let result = Utils.merge(target: target, source: source)
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))

        let valueArray = resultDict["foo"] as! [Any]
        #expect(valueArray.count == 3)
    }

    @Test("Utils.merge - merges two lists into a list")
    func testMergeTwoListsIntoList() async throws {
        let result1 = Utils.merge(target: ["foo"], source: ["bar", "xyzzy"])
        let resultArray1 = result1 as! [String]
        #expect(resultArray1 == ["foo", "bar", "xyzzy"])

        let result2 = Utils.merge(target: ["foo": ["baz"]], source: ["foo": ["bar", "xyzzy"]])
        let resultDict2 = result2 as! [String: Any]
        #expect(resultDict2.keys.contains("foo"))

        let valueArray = resultDict2["foo"] as! [String]
        #expect(valueArray.count == 3)
    }

    @Test("Utils.merge - merges two sets into a list")
    func testMergeTwoSetsIntoList() async throws {
        let result1 = Utils.merge(target: Set(["foo"]), source: Set(["bar", "xyzzy"]))
        let resultSet1 = result1 as! Set<AnyHashable>
        #expect(resultSet1.contains("foo"))
        #expect(resultSet1.contains("bar"))
        #expect(resultSet1.contains("xyzzy"))

        let result2 = Utils.merge(
            target: ["foo": Set(["baz"])], source: ["foo": Set(["bar", "xyzzy"])])
        let resultDict2 = result2 as! [String: Any]
        #expect(resultDict2.keys.contains("foo"))
    }

    @Test("Utils.merge - merges a set into a list")
    func testMergeSetIntoList() async throws {
        let result = Utils.merge(target: ["foo": ["baz"]], source: ["foo": Set(["bar"])])
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))

        let valueArray = resultDict["foo"] as! [String]
        #expect(valueArray.contains("baz"))
        #expect(valueArray.contains("bar"))
    }

    @Test("Utils.merge - merges a list into a set")
    func testMergeListIntoSet() async throws {
        let result = Utils.merge(target: ["foo": Set(["baz"])], source: ["foo": ["bar"]])
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))

        let valueSet = resultDict["foo"] as! Set<AnyHashable>
        #expect(valueSet.contains("baz"))
        #expect(valueSet.contains("bar"))
    }

    @Test("Utils.merge - merges a set into a list with multiple elements")
    func testMergeSetIntoListMultipleElements() async throws {
        let result = Utils.merge(target: ["foo": ["baz"]], source: ["foo": Set(["bar", "xyzzy"])])
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))

        let valueArray = resultDict["foo"] as! [String]
        #expect(valueArray.count == 3)
    }

    @Test("Utils.merge - merges an object into a list")
    func testMergeObjectIntoList() async throws {
        let result = Utils.merge(target: ["foo": ["bar"]], source: ["foo": ["baz": "xyzzy"]])
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))
    }

    @Test("Utils.merge - merges a list into an object")
    func testMergeListIntoObject() async throws {
        let result = Utils.merge(target: ["foo": ["bar": "baz"]], source: ["foo": ["xyzzy"]])
        let resultDict = result as! [String: Any]
        #expect(resultDict.keys.contains("foo"))
    }

    @Test("Utils.merge - merge set with undefined with another set")
    func testMergeSetWithUndefinedWithAnotherSet() async throws {
        let undefined = Undefined()

        let result1 = Utils.merge(
            target: ["foo": Set<AnyHashable>(["bar"])],
            source: ["foo": Set<AnyHashable>([undefined, "baz"])]
        )
        let resultDict1 = result1 as! [String: Any]
        #expect(resultDict1.keys.contains("foo"))

        let valueSet1 = resultDict1["foo"] as! Set<AnyHashable>
        #expect(valueSet1.contains("bar"))
        #expect(valueSet1.contains("baz"))

        let result2 = Utils.merge(
            target: ["foo": Set<AnyHashable>([undefined, "bar"])],
            source: ["foo": Set<AnyHashable>(["baz"])]
        )
        let resultDict2 = result2 as! [String: Any]
        #expect(resultDict2.keys.contains("foo"))
    }

    @Test("Utils.merge - merge set of Maps with another set of Maps")
    func testMergeSetOfMapsWithAnotherSetOfMaps() async throws {
        let result1 = Utils.merge(
            target: Set<AnyHashable>([["bar": "baz"]]),
            source: Set<AnyHashable>([["baz": "xyzzy"]])
        )
        let resultSet1 = result1 as! Set<AnyHashable>
        #expect(resultSet1.count >= 1)

        let result2 = Utils.merge(
            target: ["foo": Set<AnyHashable>([["bar": "baz"]])],
            source: ["foo": Set<AnyHashable>([["baz": "xyzzy"]])]
        )
        let resultDict2 = result2 as! [String: Any]
        #expect(resultDict2.keys.contains("foo"))
    }

    // MARK: - Utils.combine tests

    @Test("Utils.combine - combines both lists")
    func testCombineBothLists() async throws {
        let a = [1]
        let b = [2]
        let combined: [Int] = Utils.combine(a, b)

        // Verify original arrays are unchanged
        #expect(a == [1])
        #expect(b == [2])

        // Verify the combined result
        #expect(combined == [1, 2])
    }

    @Test("Utils.combine - combines one list and one non-list")
    func testCombineOneListOneNonList() async throws {
        let aN = 1
        let a = [aN]
        let bN = 2
        let b = [bN]

        let combinedAnB: [Int] = Utils.combine(aN, b)
        #expect(b == [bN])
        #expect(combinedAnB == [1, 2])

        let combinedABn: [Int] = Utils.combine(a, bN)
        #expect(a == [aN])
        #expect(combinedABn == [1, 2])
    }

    @Test("Utils.combine - combines neither is a list")
    func testCombineNeitherIsList() async throws {
        let a = 1
        let b = 2
        let combined: [Int] = Utils.combine(a, b)

        #expect(combined == [1, 2])
    }

    @Test("Utils.combine - preserves order when combining list and scalar")
    func testCombineListAndScalarPreservesOrder() async throws {
        let result1: [String] = Utils.combine(["a"], "b")
        #expect(result1 == ["a", "b"])

        let result2: [Int] = Utils.combine(1, [2, 3])
        #expect(result2 == [1, 2, 3])
    }

    // MARK: - Utils.interpretNumericEntities tests

    @Test("Utils.interpretNumericEntities - returns input unchanged when there are no entities")
    func testInterpretNumericEntitiesNoEntities() async throws {
        #expect(Utils.interpretNumericEntities("hello world") == "hello world")
        #expect(Utils.interpretNumericEntities("100% sure") == "100% sure")
    }

    @Test("Utils.interpretNumericEntities - decodes a single decimal entity")
    func testInterpretNumericEntitiesSingleDecimal() async throws {
        #expect(Utils.interpretNumericEntities("A = &#65;") == "A = A")
        #expect(Utils.interpretNumericEntities("&#48;&#49;&#50;") == "012")
    }

    @Test("Utils.interpretNumericEntities - decodes multiple entities in a sentence")
    func testInterpretNumericEntitiesMultipleEntities() async throws {
        let input = "Hello &#87;&#111;&#114;&#108;&#100;!"
        let expected = "Hello World!"
        #expect(Utils.interpretNumericEntities(input) == expected)
    }

    @Test(
        "Utils.interpretNumericEntities - decodes surrogate pair represented as two decimal entities (emoji)"
    )
    func testInterpretNumericEntitiesSurrogatePairEmoji() async throws {
        // U+1F4A9 (💩) as surrogate halves: 55357 (0xD83D), 56489 (0xDCA9)
        #expect(Utils.interpretNumericEntities("&#55357;&#56489;") == "💩")
    }

    @Test("Utils.interpretNumericEntities - entities can appear at string boundaries")
    func testInterpretNumericEntitiesStringBoundaries() async throws {
        #expect(Utils.interpretNumericEntities("&#65;BC") == "ABC")
        #expect(Utils.interpretNumericEntities("ABC&#33;") == "ABC!")
        #expect(Utils.interpretNumericEntities("&#65;") == "A")
    }

    @Test("Utils.interpretNumericEntities - mixes literals and entities")
    func testInterpretNumericEntitiesMixedLiteralsEntities() async throws {
        // '=' is 61
        #expect(Utils.interpretNumericEntities("x&#61;y") == "x=y")
        #expect(Utils.interpretNumericEntities("x=&#61;y") == "x==y")
    }

    @Test("Utils.interpretNumericEntities - malformed or unsupported patterns remain unchanged")
    func testInterpretNumericEntitiesMalformedPatternsUnchanged() async throws {
        // No digits
        #expect(Utils.interpretNumericEntities("&#;") == "&#;")
        // Missing terminating semicolon
        #expect(Utils.interpretNumericEntities("&#12") == "&#12")
        // Hex form not supported by this decoder
        #expect(Utils.interpretNumericEntities("&#x41;") == "&#x41;")
        // Space inside
        #expect(Utils.interpretNumericEntities("&# 12;") == "&# 12;")
        // Negative / non-digit after '#'
        #expect(Utils.interpretNumericEntities("&#-12;") == "&#-12;")
        // Mixed garbage
        #expect(Utils.interpretNumericEntities("&#+;") == "&#+;")
    }

    @Test("Utils.interpretNumericEntities - out-of-range code points remain unchanged")
    func testInterpretNumericEntitiesOutOfRangeUnchanged() async throws {
        // Max valid is 0x10FFFF (1114111). One above should be left as literal.
        #expect(Utils.interpretNumericEntities("&#1114112;") == "&#1114112;")
    }

    // MARK: - Utils.apply tests

    @Test("Utils.apply - apply on scalar and list")
    func testApplyScalarAndList() async throws {
        let scalarResult = Utils.apply(3) { (x: Int) in x * 2 } as? Int
        #expect(scalarResult == 6)

        let listResult = Utils.apply([1, 2]) { (x: Int) in x + 1 } as? [Int]
        #expect(listResult == [2, 3])
    }

    // MARK: - Utils.isNonNullishPrimitive and isEmpty tests

    @Test(
        "Utils.isNonNullishPrimitive - treats URL as primitive, honors skipNulls for empty string")
    func testIsNonNullishPrimitiveUrlAndEmptyString() async throws {
        #expect(Utils.isNonNullishPrimitive(URL(string: "https://example.com")!) == true)
        #expect(Utils.isNonNullishPrimitive("", skipNulls: true) == false)
    }

    @Test("Utils.isEmpty - empty collections and maps")
    func testIsEmptyCollectionsAndMaps() async throws {
        let emptyDict: [String: Any?] = [:]
        #expect(Utils.isEmpty(emptyDict) == true)
    }

    // MARK: - Utils.deepBridgeToAnyIterative

    // We keep TWO tests on purpose:
    //
    // 1) `testDecode_DeepMaps_NoTimeout_Safe`
    //    - Runs on a worker thread (no @MainActor), with a conservative depth.
    //    - Goal: cover normal decode + bridge path without tripping ARC’s recursive deinit.
    //    - If this ever fails with EXC_BAD_ACCESS in `Swift._DictionaryStorage.deinit`,
    //      reduce `depth` or investigate changes that reintroduced recursion.
    //
    // 2) `testDecode_DeepMaps_VeryDeep_Main` (@MainActor, DEBUG-only)
    //    - Stress test for extremely deep single-key chains (e.g. > 3k).
    //    - We run it on the main thread because the main thread typically has a larger stack.
    //      Even though `deepBridgeToAnyIterative` is iterative, ARC can still deallocate
    //      long linear dictionary chains recursively, which can blow the smaller stacks
    //      of worker threads.
    //    - Sanitizers (ASan/TSan/UBSan), Guard Malloc, or Malloc Stack Logging reduce headroom
    //      and may cause this test to fail at lower depths—adjust `depth` accordingly.
    //
    // Notes:
    // - Typical crash signature when stack headroom is exhausted:
    //     EXC_BAD_ACCESS in `Swift._DictionaryStorage.deinit` with a long repeating backtrace.
    // - If the stress test flakes in CI, either lower `depth`, make it @MainActor,
    //   or disable sanitizers for this test target.
    // - Search terms if you’re curious: “Swift recursive deallocation dictionary stack overflow”.
    //
    // These tests ensure the bridging code stays non-recursive and robust for deep chains,
    // while keeping CI stable.
    @Test("deep maps do not time out (safe depth)")
    func testDecode_DeepMaps_NoTimeout_Safe() throws {
        /// Conservative depth to avoid ARC’s recursive deinit on worker-thread stacks.
        let depth = 2500
        var s = "foo"
        for _ in 0..<depth { s += "[p]" }
        s += "=bar"

        let r = try Qs.decode(s, options: .init(depth: depth))
        #expect(r.keys.contains("foo"))
    }

    #if DEBUG && os(macOS)
        @MainActor
        @Test("bridge tolerates very deep single-key maps on MainActor")
        func testDecode_DeepMaps_VeryDeep_Main() {
            let depth = 6000
            var leaf: Any? = "bar"
            for _ in 0..<depth { leaf = ["p": leaf] }

            let root: [String: Any?] = ["foo": leaf]
            let bridged = Utils.deepBridgeToAnyIterative(root) as! [String: Any]

            #expect(bridged["foo"] != nil)
        }
    #endif

    @Test("dropOnMainThread eventually releases")
    func DropOnMain_Releases() async {
        weak var weakRef: AnyObject?
        do {
            let deep = [
                "k": (0..<6000).reduce(into: ["p": Any?("x")]) { acc, _ in acc = ["p": acc] }
            ]
            let box = Holder(deep)
            weakRef = box
            Utils.dropOnMainThread(box)  // schedule last release on main
        }

        // Pump the main runloop a few times so the async release runs.
        for _ in 0..<4 {
            await MainActor.run {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
            }
        }

        #expect(weakRef == nil)
    }
}

// MARK: - Helpers

private final class Holder: CustomStringConvertible {
    var payload: Any?
    init(_ p: Any?) { payload = p }
    var description: String { "Holder(payload: …)" }  // prevents recursive dictionary dump
}

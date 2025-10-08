import Foundation
import OrderedCollections
@_spi(Testing) @testable import QsSwift

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
        let out: [AnyHashable : Any] = result as! [AnyHashable: Any]
        // Compare contents directly to avoid NSNumber/Int key-bridging differences on Linux
        #expect(out.count == 2)
        #expect(out[AnyHashable(0)] as? String == "a")
        #expect(out[AnyHashable(1)] as? String == "b")
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

    @Test("Utils.merge - array overlay with Undefined preserves/replaces by index (default options)")
    func testMergeArrayOverlayWithUndefined_Default() async throws {
        let target: [Any?] = ["x", Undefined(), "z"]
        let source: [Any?] = [Undefined(), "Y", Undefined()]
        let merged = Utils.merge(target: target, source: source) as! [Any?]
        #expect(merged.count == 3)
        #expect(merged[0] as? String == "x")  // undefined in source leaves target
        #expect(merged[1] as? String == "Y")  // replaced
        #expect(merged[2] as? String == "z")  // undefined in source leaves target
    }

    @Test("Utils.merge - array overlay with parseLists=false prunes remaining Undefined")
    func testMergeArrayOverlayWithUndefined_ParseListsFalsePrunes() async throws {
        let target: [Any?] = [Undefined(), "b", Undefined()]
        let source: [Any?] = [Undefined(), Undefined()]
        let opts = DecodeOptions(parseLists: false)
        let merged = Utils.merge(target: target, source: source, options: opts) as! [Any?]
        // remaining Undefined entries are pruned under parseLists=false
        #expect(merged.count == 1)
        #expect(merged[0] as? String == "b")
    }

    @Test("Utils.merge - non-sequence source appends to array")
    func testMergeArrayWithNonSequenceSourceAppends() async throws {
        let target: [Any] = ["a", "b"]
        let merged = Utils.merge(target: target, source: 42) as! [Any]
        #expect(merged.count == 3)
        #expect(merged[0] as? String == "a")
        #expect(merged[1] as? String == "b")
        #expect(merged[2] as? Int == 42)
    }

    @Test("Utils.merge - set target stays Set<AnyHashable> and ignores Undefined in source")
    func testMergeSetTargetPreservesTypeAndIgnoresUndefined() async throws {
        let undefined = Undefined()
        let target = Set<AnyHashable>(["a"])
        let source: [Any?] = [undefined, "c", "a"]
        let merged = Utils.merge(target: target, source: source) as! Set<AnyHashable>
        #expect(merged.contains("a"))
        #expect(merged.contains("c"))
        #expect(merged.count == 2)
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

    @Test("Utils.interpretNumericEntities - hex form basic cases (lower/upper X and hex digits)")
    func testInterpretNumericEntitiesHexBasicCases() async throws {
        // lower/upper X supported
        #expect(Utils.interpretNumericEntities("&#x41;") == "A")
        #expect(Utils.interpretNumericEntities("&#X41;") == "A")
        // sequence of hex entities
        #expect(Utils.interpretNumericEntities("&#x41;&#x42;&#x43;") == "ABC")
        // lowercase hex digits
        #expect(Utils.interpretNumericEntities("&#x4a;") == "J")  // 0x4A = 'J'
    }

    @Test("Utils.interpretNumericEntities - hex form handles supplementary planes and surrogate halves")
    func testInterpretNumericEntitiesHexSupplementary() async throws {
        // Single hex entity in supplementary plane
        #expect(Utils.interpretNumericEntities("&#x1F4A9;") == "💩")
        #expect(Utils.interpretNumericEntities("&#x1F600;") == "😀")
        // Surrogate halves expressed in hex pair up
        #expect(Utils.interpretNumericEntities("&#xD83D;&#xDCA9;") == "💩")
        #expect(Utils.interpretNumericEntities("&#xD83D;&#xDE00;") == "😀")
    }

    @Test("Utils.interpretNumericEntities - hex boundaries and invalid remain literal")
    func testInterpretNumericEntitiesHexBoundariesAndInvalid() async throws {
        // Highest valid scalar decodes
        let maxScalar = String(UnicodeScalar(0x10FFFF)!)
        #expect(Utils.interpretNumericEntities("&#x10FFFF;") == maxScalar)
        // One past max remains literal
        #expect(Utils.interpretNumericEntities("&#x110000;") == "&#x110000;")
        // Missing digits and bad hex stay literal
        #expect(Utils.interpretNumericEntities("&#x;") == "&#x;")
        #expect(Utils.interpretNumericEntities("&#xZZ;") == "&#xZZ;")
    }

    @Test("Utils.interpretNumericEntities - hex entities in context")
    func testInterpretNumericEntitiesHexInContext() async throws {
        // '=' is 0x3D
        #expect(Utils.interpretNumericEntities("x&#x3D;y") == "x=y")
        // mixed case and multiple
        #expect(Utils.interpretNumericEntities("&#x65;&#88;&#x63;") == "eXc")
        // boundaries
        #expect(Utils.interpretNumericEntities("&#x41;BC") == "ABC")
        #expect(Utils.interpretNumericEntities("ABC&#x21;") == "ABC!")
    }

    @Test("Utils.interpretNumericEntities - mixed base surrogate halves")
    func testInterpretNumericEntitiesMixedSurrogates() async throws {
        // High surrogate decimal, low surrogate hex
        #expect(Utils.interpretNumericEntities("&#55357;&#xDCA9;") == "💩")
        // High surrogate hex, low surrogate decimal
        #expect(Utils.interpretNumericEntities("&#xD83D;&#56489;") == "💩")
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
        #expect(Utils.isNonNullishPrimitive(URL(string: "https://example.com")!, skipNulls: true) == true)
        #expect(Utils.isNonNullishPrimitive("", skipNulls: true) == false)
    }

    @Test("Utils.isEmpty - empty collections and maps")
    func testIsEmptyCollectionsAndMaps() async throws {
        let emptyDict: [String: Any?] = [:]
        let emptyOrderedStrings: OrderedDictionary<String, Any> = [:]
        var emptyOrderedHashable: OrderedDictionary<AnyHashable, Any> = [:]
        #expect(Utils.isEmpty(nil as Any?) == true)
        #expect(Utils.isEmpty(emptyDict) == true)
        #expect(Utils.isEmpty(emptyOrderedStrings) == true)
        #expect(Utils.isEmpty(emptyOrderedHashable) == true)
        emptyOrderedHashable[AnyHashable("filled")] = 1
        #expect(Utils.isEmpty(emptyOrderedHashable) == false)
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

    @Test("Utils.compact removes Undefined entries and normalizes nested containers")
    func utils_compact_removesUndefined() {
        let undefined = Undefined.instance

        // Dictionary branch: drop undefined keys, keep others intact
        var dictRoot: [String: Any?] = [
            "dict": ["keep": "value", "drop": undefined] as [String: Any?]
        ]
        let dictCompacted = Utils.compact(&dictRoot, allowSparseLists: false)
        if let dict = dictCompacted["dict"] as? [String: Any?] {
            #expect(dict["drop"] == nil)
            #expect(dict["keep"] as? String == "value")
        } else {
            Issue.record("Expected dictionary branch result")
        }

        // Array branch: remove Undefined, recurse into dictionaries and arrays
        var arrayRoot: [String: Any?] = [
            "array": [
                undefined,
                ["nestedDrop": undefined, "nestedKeep": "ok"] as [String: Any?],
                [undefined, "leaf"] as [Any],
                "end"
            ] as [Any]
        ]
        let arrayCompacted = Utils.compact(&arrayRoot, allowSparseLists: false)
        if let array = arrayCompacted["array"] as? [Any] {
            #expect(array.count == 3)
            #expect(!array.contains { $0 is Undefined })
            let nestedDict = array.first { $0 is [String: Any?] } as? [String: Any?]
            #expect(nestedDict?["nestedDrop"] == nil)
            #expect(nestedDict?["nestedKeep"] as? String == "ok")
        } else {
            Issue.record("Expected array branch result")
        }

        // Optional-array branch: nil → NSNull, Undefined removed
        var optionalRoot: [String: Any?] = [
            "optional": [Optional<Any>.none, Optional<Any>.some(undefined), Optional<Any>.some("tail")] as [Any?]
        ]
        let optionalCompacted = Utils.compact(&optionalRoot, allowSparseLists: false)
        if let optional = optionalCompacted["optional"] {
            #expect(!Utils.containsUndefined(optional))
        } else {
            Issue.record("Expected optional array branch result")
        }
    }

    @Test("Utils.compact preserves sparse lists when requested")
    func utils_compact_allowSparseKeepsPlaceholders() {
        let undefined = Undefined.instance
        var root: [String: Any?] = [
            "list": [undefined, "x"],
            "optionalList": [Optional<Any>.some(undefined), Optional<Any>.some("y")]
        ]

        let compacted = Utils.compact(&root, allowSparseLists: true)

        if let list = compacted["list"] as? [Any] {
            #expect(list.first is NSNull)
            #expect(list.last as? String == "x")
        }

        if let optionalList = compacted["optionalList"] as? [Any] {
            #expect(optionalList.first is NSNull)
            #expect(optionalList.last as? String == "y")
        }
    }

    @Test("Utils.compactToAny drops Undefined and normalizes optionals")
    func utils_compactToAny_normalizes() {
        let undefined = Undefined.instance
        let input: [String: Any?] = [
            "drop": undefined,
            "dict": ["inner": undefined, "keep": "value"],
            "array": [Optional<Any>.some(undefined), Optional<Any>.none, Optional<Any>.some("z")]
        ]

        let out = Utils.compactToAny(input, allowSparseLists: true)

        #expect(out["drop"] == nil)

        if let dict = out["dict"] as? [String: Any] {
            #expect(dict["inner"] == nil)
            #expect(dict["keep"] as? String == "value")
        } else {
            Issue.record("dict missing after compactToAny")
        }

        if let array = out["array"] as? [Any] {
            #expect(array.first is NSNull)
            #expect(array[1] is NSNull)
            #expect(array.last as? String == "z")
        } else {
            Issue.record("array missing after compactToAny")
        }
    }

    @Test("Utils.compactToAny normalizes nested optional arrays")
    func utils_compactToAny_nestedOptionals() {
        let input: [String: Any?] = [
            "array": [Optional<Any>.none, [Optional<Any>.none, Optional<Any>.some("value")]]
        ]

        let out = Utils.compactToAny(input, allowSparseLists: true)
        if let array = out["array"] as? [Any] {
            #expect(array.first is NSNull)
            if let nested = array.last as? [Any] {
                #expect(nested.first is NSNull)
                #expect(nested.last as? String == "value")
            } else {
                Issue.record("Expected nested array after normalization")
            }
        } else {
            Issue.record("array missing after compactToAny nested normalization")
        }
    }

    @Test("Utils.compact handles optional arrays when allowSparse=true")
    func utils_compact_optionalArrays() async throws {
        let undefined = Undefined.instance
        let optionalArray: [Any?] = ["first", nil, undefined]
        var root: [String: Any?] = ["opt": optionalArray]

        let compacted = Utils.compact(&root, allowSparseLists: true)
        if let arr = compacted["opt"] as? [Any] {
            #expect(arr.count == 3)
            #expect(arr[0] as? String == "first")
            #expect(arr[1] is NSNull)
            #expect(arr[2] is NSNull)
        } else {
            Issue.record("optional array branch missing")
        }
    }

    @Test("Utils.compact normalizes nested optional arrays with allowSparse=true")
    func utils_compact_nestedOptionalArrays() {
        let undefined = Undefined.instance
        let nested: [Any?] = ["inner", nil, undefined]
        var root: [String: Any?] = ["opt": [nested, nil, undefined]]

        let compacted = Utils.compact(&root, allowSparseLists: true)
        if let arr = compacted["opt"] as? [Any] {
            #expect(arr.count == 3)
            let inner = arr.first as? [Any]
            #expect(inner?.count == 3)
            #expect(inner?[0] as? String == "inner")
            #expect(inner?[1] is NSNull)
            #expect(inner?[2] is NSNull)
            #expect(arr[1] is NSNull)
            #expect(arr[2] is NSNull)
        } else {
            Issue.record("nested optional array not bridged")
        }
    }

    @Test("Utils.compact visits Swift [Any] arrays and preserves NSNull placeholders")
    func utils_compact_swiftArrayBranch() {
        let undefined = Undefined.instance
        var root: [String: Any?] = [
            "list": [Any](arrayLiteral: "value", undefined, ["drop": undefined])
        ]

        let compacted = Utils.compact(&root, allowSparseLists: true)
        if let list = compacted["list"] as? [Any] {
            #expect(list.count == 3)
            #expect(list[0] as? String == "value")
            #expect(list[1] is NSNull)
            let dict = list[2] as? [String: Any]
            #expect(dict?.isEmpty == true)
        } else {
            Issue.record("Swift [Any] branch not exercised")
        }
    }

    @Test("Utils.compact prunes Undefined in Swift [Any] when allowSparse=false")
    func utils_compact_swiftArrayDropsUndefined_noSparse() {
        let undefined = Undefined.instance
        var root: [String: Any?] = [
            "list": [Any](arrayLiteral: "keep", undefined, ["inner": undefined])
        ]

        let compacted = Utils.compact(&root)
        if let list = compacted["list"] as? [Any] {
            #expect(list.count == 2)
            #expect(list.first as? String == "keep")
            let nested = list.last as? [String: Any]
            #expect(nested?.isEmpty == true)
        } else {
            Issue.record("Swift [Any] allowSparse=false branch not exercised")
        }
    }

    @Test("Utils.compact handles Swift [Any] containing nested [Any?]")
    func utils_compact_swiftArrayNestedOptionals() {
        let nested: [Any?] = ["inner", nil]
        var root: [String: Any?] = ["list": [Any](arrayLiteral: nested)]

        let compacted = Utils.compact(&root, allowSparseLists: true)
        if let list = compacted["list"] as? [Any], let inner = list.first as? [Any] {
            #expect(inner.count == 2)
            #expect(inner[0] as? String == "inner")
            #expect(inner[1] is NSNull)
        } else {
            Issue.record("Nested optional arrays not compacted as expected")
        }
    }

    @Test("Utils.compact normalizes optional elements that wrap [Any?] payloads")
    func utils_compact_optionalElementsWrappingOptionalArrays() {
        let undefined = Undefined.instance
        let inner: [Any?] = [undefined, "leaf", nil]
        var root: [String: Any?] = ["list": [Any?](arrayLiteral: inner, nil)]

        let compacted = Utils.compact(&root, allowSparseLists: true)
        if let list = compacted["list"] as? [Any] {
            #expect(list.count == 2)
            let nested = list.first as? [Any]
            #expect(nested?.contains { ($0 as? String) == "leaf" } == true)
            #expect(nested?.contains { $0 is NSNull } == true)
            #expect(list.last is NSNull)
        } else {
            Issue.record("Expected compacted list for nested optional arrays")
        }
    }

    @Test("Utils.compact handles Foundation arrays and nested optionals across sparse modes")
    func utils_compact_foundationAndNestedBranches() {
        let undefined = Undefined.instance
        let nestedOptional: [Any?] = [
            undefined,
            ["deep": undefined, "keep": "value"] as [String: Any?],
            nil,
            "leaf"
        ]
        let optionalList: [Any?] = [undefined, nestedOptional, undefined]
        let foundationArray: NSArray = [undefined, ["inner": undefined], nestedOptional, "scalar"]
        let plainArray: [Any] = [undefined, ["inner": undefined], "plain"]

        var sparseRoot: [String: Any?] = [
            "drop": undefined,
            "foundation": foundationArray,
            "optional": optionalList,
            "plain": plainArray
        ]

        let sparse = Utils.compact(&sparseRoot, allowSparseLists: true)
        #expect(sparse["drop"] == nil)

        if let foundation = sparse["foundation"] as? [Any] {
            #expect(foundation.first is NSNull)
            let emptied = foundation.compactMap { $0 as? [String: Any] }.first
            #expect(emptied?.isEmpty == true)
            let nested = foundation.compactMap { $0 as? [Any] }.first
            #expect(nested?.first is NSNull)
        } else {
            Issue.record("Foundation-backed array branch not exercised")
        }

        if let optional = sparse["optional"] as? [Any] {
            #expect(optional.first is NSNull)
            if let nested = optional.dropFirst().first as? [Any] {
                #expect(nested.first is NSNull)
                let nestedDict = nested.compactMap { $0 as? [String: Any] }.first
                #expect(nestedDict?.keys.contains("keep") == true)
                #expect(nested.last as? String == "leaf")
            } else {
                Issue.record("Nested optional array not normalized")
            }
            #expect(optional.last is NSNull)
        } else {
            Issue.record("Optional array branch not exercised")
        }

        if let plain = sparse["plain"] as? [Any] {
            #expect(plain.first is NSNull)
            #expect(plain.contains { ($0 as? String) == "plain" })
        } else {
            Issue.record("Swift [Any] branch not exercised")
        }

        var denseRoot: [String: Any?] = [
            "foundation": foundationArray,
            "optional": optionalList,
            "plain": plainArray
        ]

        let dense = Utils.compact(&denseRoot)
        if let foundationDense = dense["foundation"] as? [Any] {
            #expect(!foundationDense.contains { $0 is NSNull })
        } else {
            Issue.record("Foundation array (no sparse) not exercised")
        }

        if let optionalDense = dense["optional"] as? [Any] {
            #expect(optionalDense.contains { $0 is NSNull } == false)
        } else {
            Issue.record("Optional array (no sparse) not exercised")
        }

        if let plainDense = dense["plain"] as? [Any] {
            #expect(plainDense.contains { $0 is NSNull } == false)
        } else {
            Issue.record("Swift [Any] (no sparse) not exercised")
        }
    }

    @Test("Utils.compactToAny normalizes dictionary elements in arrays and explicit nil roots")
    func utils_compactToAny_dictElementsAndNilRoots() {
        let undefined = Undefined.instance
        let nestedDict: [String: Any?] = [
            "inner": undefined,
            "value": 9
        ]
        let nestedOptional: [Any?] = [undefined, ["deep": undefined, "keep": "leaf"] as [String: Any?]]
        let input: [String: Any?] = [
            "list": [undefined, nestedDict, nestedOptional, nil],
            "noneRoot": nil
        ]

        let sparse = Utils.compactToAny(input, allowSparseLists: true)
        if let list = sparse["list"] as? [Any] {
            #expect(list.count == 4)
            #expect(list[0] is NSNull)

            let dict = list[1] as? [String: Any]
            #expect(dict?["inner"] == nil)
            #expect(dict?["value"] as? Int == 9)

            if let nested = list[2] as? [Any] {
                #expect(nested.first is NSNull)
                let tail = nested.last as? [String: Any]
                #expect(tail?["keep"] as? String == "leaf")
                #expect(tail?["deep"] == nil)
            } else {
                Issue.record("Expected nested optional array normalization")
            }

            #expect(list[3] is NSNull)
        } else {
            Issue.record("Sparse list normalization failed")
        }

        #expect(sparse["noneRoot"] is NSNull)

        let dense = Utils.compactToAny(input, allowSparseLists: false)
        if let denseList = dense["list"] as? [Any] {
            #expect(!denseList.contains { $0 is Undefined })
            #expect(denseList.contains { $0 is NSNull })
        } else {
            Issue.record("Dense list normalization failed")
        }
    }


    @Test("Utils.containsUndefined detects sentinel in nested structures")
    func utils_containsUndefined_detects() {
        let undefined = Undefined.instance
        let sample: [String: Any?] = [
            "array": [undefined, "x"],
            "dict": ["inner": undefined]
        ]

        #expect(Utils.containsUndefined(sample))

        var compacted = sample
        _ = Utils.compact(&compacted)
        #expect(!Utils.containsUndefined(compacted))
    }

    @Test("Utils.containsUndefined inspects Swift [Any] roots")
    func utils_containsUndefined_swiftArrayRoot() {
        let payload: [Any] = ["value", Undefined.instance]
        #expect(Utils.containsUndefined(payload))
    }

    @Test("Utils.containsUndefined reports true for direct sentinel input")
    func utils_containsUndefined_directSentinel() {
        #expect(Utils.containsUndefined(Undefined.instance))
    }

    @Test("Utils.estimateSingleKeyChainDepth traverses AnyHashable optional chains")
    func utils_estimateSingleKeyChainDepth_optionalChain() {
        let level2: [AnyHashable: Any?] = [AnyHashable("c"): nil]
        let level1: [AnyHashable: Any?] = [AnyHashable("b"): level2]
        let root: [AnyHashable: Any?] = [AnyHashable("a"): level1]
        #expect(Utils.estimateSingleKeyChainDepth(root, cap: 10) == 3)
    }

    @Test("Utils.estimateSingleKeyChainDepth traverses AnyHashable non-optional chains")
    func utils_estimateSingleKeyChainDepth_nonOptionalChain() {
        let child: [AnyHashable: Any] = [AnyHashable(2): "end"]
        let root: [AnyHashable: Any] = [AnyHashable(1): child]
        #expect(Utils.estimateSingleKeyChainDepth(root, cap: 10) == 2)
    }

    @Test("Utils.merge handles heterogeneous containers")
    func utils_merge_coversBranches() {
        let undefined = Undefined.instance

        // [Any?] target merged with dictionary source
        let targetArray: [Any?] = ["a", nil, undefined]
        let sourceDict: [AnyHashable: Any] = ["extra": "value"]
        let merged1 = Utils.merge(target: targetArray, source: sourceDict, options: .init())
        #expect(merged1 is [AnyHashable: Any])
        if let mergedDict1 = merged1 as? [AnyHashable: Any] {
            #expect(mergedDict1["extra"] as? String == "value")
            #expect(mergedDict1[0] as? String == "a")
        }

        // Dictionary target merged with array source
        let merged2 = Utils.merge(target: merged1, source: [undefined, "tail"], options: .init())
        #expect(merged2 is [AnyHashable: Any])

        // OrderedSet union and sequence merging
        let ordered = OrderedSet<AnyHashable>([1, 2])
        let mergedOrdered = Utils.merge(target: ordered, source: OrderedSet([2, 3]), options: .init())
        #expect(mergedOrdered is OrderedSet<AnyHashable>)
        if let orderedResult = mergedOrdered as? OrderedSet<AnyHashable> {
            #expect(!orderedResult.isEmpty)
        }

        let orderedWithSequence = Utils.merge(target: OrderedSet(["a"]), source: [undefined, "b"], options: .init())
        if let orderedSequenceArray = orderedWithSequence as? [Any?] {
            #expect(orderedSequenceArray.contains { ($0 as? String) == "b" })
        }

        // Set union and sequence merging
        let mergedSet = Utils.merge(target: Set([1, 2]), source: [undefined, 3], options: .init())
        if let setResult = mergedSet as? Set<AnyHashable> {
            #expect(setResult.contains { ($0 as? Int) == 3 })
        }

        // Array target with Undefined elements and parseLists disabled
        let options = DecodeOptions(parseLists: false)
        let arrayWithUndefined: [Any] = [undefined, "a"]
        let mergedArray = Utils.merge(target: arrayWithUndefined, source: ["b", undefined], options: options) as? [Any]
        #expect(mergedArray?.compactMap { $0 as? String }.contains("b") == true)

        // Array target + sequence of maps to trigger recursive merge
        let targetMaps: [Any] = [["k": "v"], Undefined.instance]
        let sourceMaps: [Any] = [["k": "override"], ["new": "value"]]
        if let mergedMaps = Utils.merge(target: targetMaps, source: sourceMaps, options: .init()) as? [Any?] {
            let first = mergedMaps[0] as? [AnyHashable: Any]
            #expect(first?["k"] as? String == "override")
        }

        // Dictionary target with non-sequence source coerces key from description
        let dictTarget: [AnyHashable: Any] = ["keep": 1]
        if let mergedDict = Utils.merge(target: dictTarget, source: "flag", options: .init()) as? [AnyHashable: Any] {
            #expect(mergedDict.keys.contains { ($0 as? String) == "flag" })
        }

        // Nil target with array source produces array with filtered Undefined
        if let mergedFromNil = Utils.merge(target: nil, source: ["a", undefined], options: .init()) as? [Any?] {
            #expect(mergedFromNil.contains { ($0 as? String) == "a" })
        }
    }

    @Test("Utils.merge extends OrderedSet<AnyHashable> with sequences and skips Undefined")
    func utils_merge_orderedSet_anyHashable_sequence() {
        let undefined = Undefined.instance
        let target = OrderedSet<AnyHashable>([AnyHashable("a")])
        let merged = Utils.merge(target: target, source: [undefined, "b", "a"], options: .init())

        if let ordered = merged as? OrderedSet<AnyHashable> {
            #expect(ordered.contains("a"))
            #expect(ordered.contains("b"))
            #expect(ordered.count == 2)
        } else {
            Issue.record("OrderedSet branch did not return OrderedSet: \(String(describing: merged))")
        }

        if let unioned = Utils.merge(target: target, source: OrderedSet([AnyHashable("b")]), options: .init()) as? OrderedSet<AnyHashable> {
            #expect(unioned.elementsEqual([AnyHashable("a"), AnyHashable("b")]))
        } else {
            Issue.record("OrderedSet union branch not exercised")
        }

        if let unchanged = Utils.merge(target: target, source: undefined, options: .init()) as? OrderedSet<AnyHashable> {
            #expect(unchanged.elementsEqual(target))
        } else {
            Issue.record("OrderedSet Undefined branch not exercised")
        }
    }

    @Test("Utils.merge unions Set<AnyHashable> with sequence input")
    func utils_merge_set_anyHashable_sequence() {
        let undefined = Undefined.instance
        let target = Set<AnyHashable>(["seed"])
        let merged = Utils.merge(target: target, source: [undefined, "extra"], options: .init())

        if let setResult = merged as? Set<AnyHashable> {
            #expect(setResult.contains("seed"))
            #expect(setResult.contains("extra"))
        } else {
            Issue.record("Set branch did not return Set: \(String(describing: merged))")
        }

        if let unchanged = Utils.merge(target: target, source: undefined, options: .init()) as? Set<AnyHashable> {
            #expect(unchanged == target)
        } else {
            Issue.record("Set Undefined branch not exercised")
        }
    }

    @Test("Utils.merge overlays Swift [Any] with sequence indices")
    func utils_merge_arraySequenceOverlay() {
        let undefined = Undefined.instance
        let target = [Any](arrayLiteral: undefined, "keep")
        let source: [Any] = ["replaced", "new"]
        if let merged = Utils.merge(target: target, source: source, options: .init(parseLists: true)) as? [Any?] {
            #expect(merged[0] as? String == "replaced")
            #expect(merged[1] as? String == "new")
            #expect(merged.count == 2)
        } else {
            Issue.record("Sequence overlay branch not exercised")
        }
    }

    @Test("Utils.merge promotes array target to dictionary when merging with map")
    func utils_merge_arrayToDictionaryTarget() {
        let undefined = Undefined.instance
        let target: [Any] = ["a", undefined]
        let sourceDict: [AnyHashable: Any] = ["b": 2]
        let merged = Utils.merge(target: target, source: sourceDict, options: .init())
        if let dict = merged as? [AnyHashable: Any] {
            #expect(dict[0] as? String == "a")
            #expect(dict["b"] as? Int == 2)
        } else {
            Issue.record("Array→dictionary promotion not exercised")
        }
    }

    @Test("Utils.merge dictionary target consumes OrderedSet sequences")
    func utils_merge_dictionaryOrderedSetSequence() {
        let target: [AnyHashable: Any] = ["existing": "value"]
        let ordered = OrderedSet<AnyHashable>([AnyHashable("first"), AnyHashable(2)])

        if let merged = Utils.merge(target: target, source: ordered, options: .init()) as? [AnyHashable: Any] {
            #expect(merged["existing"] as? String == "value")
            #expect(merged[0] as? AnyHashable == AnyHashable("first"))
            #expect(merged[1] as? AnyHashable == AnyHashable(2))
        } else {
            Issue.record("OrderedSet sequence branch not exercised")
        }
    }

    @Test("Utils.merge merges nil targets with typed [Any] sources and filters Undefined")
    func utils_merge_nilTarget_typedArraySource() {
        let source: [Any] = [Undefined.instance, "ok", 42]
        if let merged = Utils.merge(target: nil, source: source, options: .init()) as? [Any?] {
            #expect(merged.count == 3)
            let head = merged.first.flatMap { $0 }
            #expect(head == nil)
            #expect(merged.dropFirst().contains { $0 is Undefined } == false)
            #expect(merged[1] as? String == "ok")
            #expect(merged[2] as? Int == 42)
        } else {
            Issue.record("Nil-target array merge branch not exercised")
        }
    }

    @Test("Utils.merge overlays arrays with scalars when no sequence is available")
    func utils_merge_arrayAppendsScalarOnNonSequenceSource() {
        let undefined = Undefined.instance
        let target: [Any] = [undefined, "keep"]
        let merged = Utils.merge(target: target, source: "tail", options: .init())

        if let out = merged as? [Any?] {
            #expect(out.count == 3)
            #expect(out.first is Undefined)
            #expect(out.last as? String == "tail")
        } else if let out = merged as? [Any] {
            #expect(out.count == 3)
            #expect(out.first is Undefined)
            #expect(out.last as? String == "tail")
        } else {
            Issue.record("Array scalar overlay branch not exercised")
        }
    }

    @Test("Utils.deepBridgeToAnyIterative handles nil roots and AnyHashable dictionaries")
    func utils_deepBridge_nilAndHashable() {
        let bridgedNil = Utils.deepBridgeToAnyIterative(nil)
        #expect(bridgedNil is NSNull)

        let dict: [AnyHashable: Any] = [
            1: ["nested": NSNull()],
            "two": 2
        ]
        let bridged = Utils.deepBridgeToAnyIterative(dict)
        if let map = bridged as? [String: Any] {
            #expect(map["1"] is [String: Any])
            #expect(map["two"] as? Int == 2)
        } else {
            Issue.record("Expected bridged dictionary, got: \(type(of: bridged))")
        }

        let optionalArray: [Any?] = [nil, "value"]
        let bridgedArray = Utils.deepBridgeToAnyIterative(optionalArray)
        if let arrOpt = bridgedArray as? [Any?] {
            switch arrOpt.first {
            case .some(.none):
                #expect(true)
            default:
                Issue.record("Expected first element to be .none")
            }

            switch arrOpt.last {
            case .some(.some(let value)):
                #expect(value as? String == "value")
            default:
                Issue.record("Expected last element to unwrap to String")
            }
        } else if let arr = bridgedArray as? [Any] {
            let first = arr.first
            let firstMirror = first.map { Mirror(reflecting: $0) }
            let firstValue = firstMirror?.displayStyle == .optional ? firstMirror?.children.first?.value : first
            #expect(firstValue is NSNull)

            let last = arr.last
            let lastMirror = last.map { Mirror(reflecting: $0) }
            let lastValue = lastMirror?.displayStyle == .optional ? lastMirror?.children.first?.value : last
            #expect(lastValue as? String == "value")
        } else {
            Issue.record("Optional array branch not exercised")
        }
    }

    @Test("Utils.needsMainDrop short-circuits when threshold is non-positive")
    func utils_needsMainDrop_thresholdShortCircuit() {
        let root: [String: Any?] = ["k": nil]
        #expect(!Utils.needsMainDrop(root, threshold: 0))
        #expect(!Utils.needsMainDrop(root, threshold: -3))
    }

    @Test("Utils.dropOnMainThread tolerates nil payloads")
    func utils_dropOnMainThread_nilPayload() {
        Utils.dropOnMainThread(nil as Any?)
        Utils.dropOnMainThread(nil as AnyObject?)
    }

    @Test("Utils.apply returns nil when the value cannot be cast to generic type")
    func utils_apply_typeMismatchReturnsNil() {
        let transformed = Utils.apply("not-an-int") { (value: Int) -> Int in value * 2 }
        #expect(transformed == nil)
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

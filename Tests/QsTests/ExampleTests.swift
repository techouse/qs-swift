import Foundation
import OrderedCollections
import Testing

@testable import Qs

@Suite("example")
struct ExampleTests {

    // Shared constants used in charset tests
    private let urlEncodedCheckmarkInUtf8 = "%E2%9C%93"
    private let urlEncodedOSlashInUtf8 = "%C3%B8"
    private let urlEncodedNumCheckmark = "%26%2310003%3B"
    private let urlEncodedNumSmiley = "%26%239786%3B"

    // MARK: - Simple examples

    @Test("simple: decodes a simple query string")
    func simple_decode() throws {
        let r = try Qs.decode("a=c")
        #expect((r["a"] as? String) == "c")
    }

    @Test("simple: encodes a simple Map to a query string")
    func simple_encode() throws {
        let s = try Qs.encode(["a": "c"])
        #expect(s == "a=c")
    }

    // MARK: - Decoding • Maps

    @Test("maps: nested with bracket notation")
    func maps_nested() throws {
        let r = try Qs.decode("foo[bar]=baz")
        let foo = r["foo"] as? [String: Any]
        #expect((foo?["bar"] as? String) == "baz")
    }

    @Test("maps: URI-encoded keys")
    func maps_uriEncodedKeys() throws {
        let r = try Qs.decode("a%5Bb%5D=c")
        let a = r["a"] as? [String: Any]
        #expect((a?["b"] as? String) == "c")
    }

    @Test("maps: deep nest")
    func maps_deepNest() throws {
        let r = try Qs.decode("foo[bar][baz]=foobarbaz")
        let foo = r["foo"] as? [String: Any]
        let bar = foo?["bar"] as? [String: Any]
        #expect((bar?["baz"] as? String) == "foobarbaz")
    }

    @Test("maps: default max depth trims remainder")
    func maps_defaultDepthTrims() throws {
        let r = try Qs.decode("a[b][c][d][e][f][g][h][i]=j")
        let a = r["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        let c = b?["c"] as? [String: Any]
        let d = c?["d"] as? [String: Any]
        let e = d?["e"] as? [String: Any]
        let f = e?["f"] as? [String: Any]
        // Kotlin expected: "f" map contains "[g][h][i]" -> "j"
        #expect((f?["[g][h][i]"] as? String) == "j")
    }

    @Test("maps: override depth with DecodeOptions.depth")
    func maps_overrideDepth() throws {
        let r = try Qs.decode("a[b][c][d][e][f][g][h][i]=j", options: .init(depth: 1))
        let a = r["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        #expect((b?["[c][d][e][f][g][h][i]"] as? String) == "j")
    }

    @Test("maps: parameterLimit")
    func maps_parameterLimit() throws {
        let r = try Qs.decode("a=b&c=d", options: .init(parameterLimit: 1))
        #expect((r["a"] as? String) == "b")
        #expect(r["c"] == nil)
    }

    @Test("maps: ignore query prefix")
    func maps_ignorePrefix() throws {
        let r = try Qs.decode("?a=b&c=d", options: .init(ignoreQueryPrefix: true))
        #expect((r["a"] as? String) == "b")
        #expect((r["c"] as? String) == "d")
    }

    @Test("maps: custom delimiter")
    func maps_customDelimiter() throws {
        let r = try Qs.decode("a=b;c=d", options: .init(delimiter: StringDelimiter(";")))
        #expect((r["a"] as? String) == "b")
        #expect((r["c"] as? String) == "d")
    }

    @Test("maps: regex delimiter")
    func maps_regexDelimiter() throws {
        let delim = try RegexDelimiter("[;,]")
        let r = try Qs.decode("a=b;c=d", options: .init(delimiter: delim))
        #expect((r["a"] as? String) == "b")
        #expect((r["c"] as? String) == "d")
    }

    @Test("maps: allowDots")
    func maps_allowDots() throws {
        let r = try Qs.decode("a.b=c", options: .init(allowDots: true))
        let a = r["a"] as? [String: Any]
        #expect((a?["b"] as? String) == "c")
    }

    @Test("maps: decodeDotInKeys")
    func maps_decodeDotInKeys() throws {
        let r = try Qs.decode(
            "name%252Eobj.first=John&name%252Eobj.last=Doe",
            options: .init(decodeDotInKeys: true)
        )
        let nameObj = r["name.obj"] as? [String: Any]
        #expect((nameObj?["first"] as? String) == "John")
        #expect((nameObj?["last"] as? String) == "Doe")
    }

    @Test("maps: allowEmptyLists")
    func maps_allowEmptyLists() throws {
        let r = try Qs.decode("foo[]&bar=baz", options: .init(allowEmptyLists: true))
        #expect((r["foo"] as? [Any])?.isEmpty == true)
        #expect((r["bar"] as? String) == "baz")
    }

    @Test("maps: duplicates default combine")
    func maps_duplicatesDefault() throws {
        let r = try Qs.decode("foo=bar&foo=baz")
        let arr = r["foo"] as? [Any]
        #expect(arr?.count == 2)
        #expect(arr?.first as? String == "bar")
        #expect(arr?.last as? String == "baz")
    }

    @Test("maps: duplicates FIRST/LAST/COMBINE")
    func maps_duplicatesModes() throws {
        var r = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .combine))
        #expect((r["foo"] as? [Any])?.count == 2)

        r = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .first))
        #expect((r["foo"] as? String) == "bar")

        r = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .last))
        #expect((r["foo"] as? String) == "baz")
    }

    @Test("maps: latin1 charset for legacy browsers")
    func maps_latin1() throws {
        let r = try Qs.decode("a=%A7", options: .init(charset: .isoLatin1))
        #expect((r["a"] as? String) == "§")
    }

    @Test("maps: charset sentinel with latin1")
    func maps_charsetSentinel_latin1() throws {
        let r = try Qs.decode(
            "utf8=\(urlEncodedCheckmarkInUtf8)&a=\(urlEncodedOSlashInUtf8)",
            options: .init(charset: .isoLatin1, charsetSentinel: true)
        )
        #expect((r["a"] as? String) == "ø")
    }

    @Test("maps: charset sentinel with utf8")
    func maps_charsetSentinel_utf8() throws {
        let r = try Qs.decode(
            "utf8=\(urlEncodedNumCheckmark)&a=%F8",
            options: .init(charset: .utf8, charsetSentinel: true)
        )
        #expect((r["a"] as? String) == "ø")
    }

    @Test("maps: interpret numeric entities")
    func maps_numericEntities() throws {
        let r = try Qs.decode(
            "a=\(urlEncodedNumSmiley)",
            options: .init(charset: .isoLatin1, interpretNumericEntities: true)
        )
        #expect((r["a"] as? String) == "☺")
    }

    // MARK: - Decoding • Lists

    @Test("lists: [] notation")
    func lists_brackets() throws {
        let r = try Qs.decode("a[]=b&a[]=c")
        let a = r["a"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?.first as? String == "b")
        #expect(a?.last as? String == "c")
    }

    @Test("lists: explicit indices")
    func lists_indices() throws {
        let r = try Qs.decode("a[1]=c&a[0]=b")
        let a = r["a"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?[0] as? String == "b")
        #expect(a?[1] as? String == "c")
    }

    @Test("lists: compact sparse preserving order")
    func lists_compactSparse() throws {
        let r = try Qs.decode("a[1]=b&a[15]=c")
        let a = r["a"] as? [Any]
        #expect(a?.count == 2)
        #expect(a?.first as? String == "b")
        #expect(a?.last as? String == "c")
    }

    @Test("lists: preserve empty string values")
    func lists_preserveEmptyStrings() throws {
        var r = try Qs.decode("a[]=&a[]=b")
        let a0 = r["a"] as? [String]
        #expect(a0 == ["", "b"])

        r = try Qs.decode("a[0]=b&a[1]=&a[2]=c")
        let a1 = r["a"] as? [String]
        #expect(a1 == ["b", "", "c"])
    }

    @Test("lists: convert high indices to map keys")
    func lists_highIndexToMap() throws {
        let r = try Qs.decode("a[100]=b")
        let a = r["a"] as? [String: Any]
        #expect((a?["100"] as? String) == "b")
    }

    @Test("lists: override list limit (0)")
    func lists_overrideListLimit0() throws {
        let r = try Qs.decode("a[1]=b", options: .init(listLimit: 0))
        let a = r["a"] as? [String: Any]
        #expect((a?["1"] as? String) == "b")
    }

    @Test("lists: disable list parsing entirely")
    func lists_disableParsing() throws {
        let r = try Qs.decode("a[]=b", options: .init(parseLists: false))
        let a = r["a"] as? [String: Any]
        #expect((a?["0"] as? String) == "b")
    }

    @Test("lists: merge mixed notations into map")
    func lists_mixedNotations() throws {
        let r = try Qs.decode("a[0]=b&a[b]=c")
        let a = r["a"] as? [String: Any]
        #expect((a?["0"] as? String) == "b")
        #expect((a?["b"] as? String) == "c")
    }

    @Test("lists: lists of maps")
    func lists_ofMaps() throws {
        let r = try Qs.decode("a[][b]=c")
        let a = r["a"] as? [Any]
        let first = a?.first as? [String: Any]
        #expect((first?["b"] as? String) == "c")
    }

    @Test("lists: comma-separated values with comma option")
    func lists_commaOption() throws {
        let r = try Qs.decode("a=b,c", options: .init(comma: true))
        let a = r["a"] as? [String]
        #expect(a == ["b", "c"])
    }

    // MARK: - Decoding • Primitive/Scalar

    @Test("scalars: all values parsed as strings by default")
    func scalars_asStrings() throws {
        let r = try Qs.decode("a=15&b=true&c=null")
        #expect((r["a"] as? String) == "15")
        #expect((r["b"] as? String) == "true")
        #expect((r["c"] as? String) == "null")
    }

    // MARK: - Encoding

    @Test("encode: maps as expected")
    func encode_maps() throws {
        #expect(try Qs.encode(["a": "b"]) == "a=b")
        #expect(try Qs.encode(["a": ["b": "c"]], options: .init()) == "a%5Bb%5D=c")
    }

    @Test("encode: encode=false leaves brackets")
    func encode_disableEncoding() throws {
        let s = try Qs.encode(["a": ["b": "c"]], options: .init(encode: false))
        #expect(s == "a[b]=c")
    }

    @Test("encode: encodeValuesOnly=true")
    func encode_valuesOnly() throws {
        let input: [String: Any] = [
            "a": "b",
            "c": ["d", "e=f"],
            "f": [["g"], ["h"]],
        ]
        let s = try Qs.encode(input, options: .init(encodeValuesOnly: true))
        #expect(s == "a=b&c[0]=d&c[1]=e%3Df&f[0][0]=g&f[1][0]=h")
    }

    @Test("encode: custom encoder")
    func encode_customEncoder() throws {
        // Helper to unwrap Optional without printing "Optional(...)"
        let unwrapOptional: @Sendable (Any) -> Any = { x in
            let m = Mirror(reflecting: x)
            if m.displayStyle == .optional, let child = m.children.first {
                return child.value
            }
            return x
        }

        let enc: ValueEncoder = { @Sendable value, _, _ in
            guard let v = value else { return "" }  // nil -> ""
            let u = unwrapOptional(v)

            if let s = u as? String, s == "č" { return "c" }
            return String(describing: u)
        }

        let s = try Qs.encode(["a": ["b": "č"]], options: .init(encoder: enc))
        #expect(s == "a[b]=c")
    }

    @Test("encode: lists with indices by default (encode=false)")
    func encode_listsDefault() throws {
        let s = try Qs.encode(["a": ["b", "c", "d"]], options: .init(encode: false))
        #expect(s == "a[0]=b&a[1]=c&a[2]=d")
    }

    @Test("encode: indices=false")
    func encode_indicesFalse() throws {
        let s = try Qs.encode(
            ["a": ["b", "c", "d"]],
            options: .init(indices: false, encode: false)
        )
        #expect(s == "a=b&a=c&a=d")
    }

    @Test("encode: different list formats")
    func encode_listFormats() throws {
        var s = try Qs.encode(
            ["a": ["b", "c"]], options: .init(listFormat: .indices, encode: false))
        #expect(s == "a[0]=b&a[1]=c")

        s = try Qs.encode(["a": ["b", "c"]], options: .init(listFormat: .brackets, encode: false))
        #expect(s == "a[]=b&a[]=c")

        s = try Qs.encode(["a": ["b", "c"]], options: .init(listFormat: .repeatKey, encode: false))
        #expect(s == "a=b&a=c")

        s = try Qs.encode(["a": ["b", "c"]], options: .init(listFormat: .comma, encode: false))
        #expect(s == "a=b,c")
    }

    @Test("encode: bracket notation for maps by default (encode=false)")
    func encode_bracketNotationForMaps() throws {
        let input: [String: Any] = ["a": ["b": ["c": "d", "e": "f"]]]
        let s = try Qs.encode(input, options: .init(encode: false))
        #expect(s == "a[b][c]=d&a[b][e]=f")
    }

    @Test("encode: dot notation with allowDots=true")
    func encode_allowDots() throws {
        let input: [String: Any] = ["a": ["b": ["c": "d", "e": "f"]]]
        let s = try Qs.encode(input, options: .init(allowDots: true, encode: false))
        #expect(s == "a.b.c=d&a.b.e=f")
    }

    @Test("encode: encodeDotInKeys=true")
    func encode_encodeDotInKeys() throws {
        let input: [String: Any] = ["name.obj": ["first": "John", "last": "Doe"]]
        let s = try Qs.encode(input, options: .init(allowDots: true, encodeDotInKeys: true))
        #expect(s == "name%252Eobj.first=John&name%252Eobj.last=Doe")
    }

    @Test("encode: allowEmptyLists=true (encode=false)")
    func encode_allowEmptyLists() throws {
        let s = try Qs.encode(
            ["foo": [Any](), "bar": "baz"],
            options: .init(allowEmptyLists: true, encode: false)
        )
        let parts = Set(s.split(separator: "&").map(String.init))
        #expect(parts == Set(["foo[]", "bar=baz"]))
    }

    @Test("encode: allowEmptyLists=true (encode=false) OrderedDictionary")
    func encode_allowEmptyLists1() throws {
        let od: OrderedDictionary<String, Any> = ["foo": [Any](), "bar": "baz"]
        let s = try Qs.encode(
            od,
            options: .init(allowEmptyLists: true, encode: false)
        )
        #expect(s == "foo[]&bar=baz")
    }

    @Test("encode: empty strings and null values")
    func encode_emptyAndNull() throws {
        #expect(try Qs.encode(["a": ""]) == "a=")
    }

    @Test("encode: empty collections → empty string")
    func encode_emptyCollections() throws {
        #expect(try Qs.encode(["a": [Any]()]) == "")
        #expect(try Qs.encode(["a": [String: Any]()]) == "")
        #expect(try Qs.encode(["a": [[String: Any]]()]) == "")
        #expect(try Qs.encode(["a": ["b": [Any]()]]) == "")
        #expect(try Qs.encode(["a": ["b": [String: Any]()]]) == "")
    }

    @Test("encode: omits undefined properties")
    func encode_omitsUndefined() throws {
        let s = try Qs.encode(["a": NSNull(), "b": Undefined()])
        #expect(s == "a=")
    }

    @Test("encode: add query prefix")
    func encode_queryPrefix() throws {
        let s = try Qs.encode(["a": "b", "c": "d"], options: .init(addQueryPrefix: true))
        #expect(s == "?a=b&c=d")
    }

    @Test("encode: override delimiter")
    func encode_overrideDelimiter() throws {
        let s = try Qs.encode(["a": "b", "c": "d"], options: .init(delimiter: ";"))
        #expect(s == "a=b;c=d")
    }

    @Test("encode: serialize Date using default serializer (encode=false)")
    func encode_dateDefault() throws {
        let date = Date(timeIntervalSince1970: 0.007)  // 7 ms since epoch
        let s = try Qs.encode(["a": date], options: .init(encode: false))
        #expect(s == "a=1970-01-01T00:00:00.007Z")
    }

    @Test("encode: custom date serializer (encode=false)")
    func encode_dateCustom() throws {
        let date = Date(timeIntervalSince1970: 0.007)
        let s = try Qs.encode(
            ["a": date],
            options: .init(
                dateSerializer: { d in String(Int((d.timeIntervalSince1970 * 1000.0).rounded())) },
                encode: false
            )
        )
        #expect(s == "a=7")
    }

    @Test("encode: sort parameter keys")
    func encode_sortKeys() throws {
        let sort: Sorter = { @Sendable a, b in
            let la = String(describing: a ?? "")
            let lb = String(describing: b ?? "")
            if la < lb { return -1 }
            if la > lb { return 1 }
            return 0
        }

        let s = try Qs.encode(
            ["a": "c", "z": "y", "b": "f"],
            options: .init(encode: false, sort: sort)
        )
        #expect(s == "a=c&b=f&z=y")
    }

    @Test("encode: filter with FunctionFilter")
    func encode_filterFunction() throws {
        let date = Date(timeIntervalSince1970: 0.123)  // 123ms
        let input: [String: Any] = [
            "a": "b",
            "c": "d",
            "e": ["f": date, "g": [2]],
        ]
        let filter = FunctionFilter { prefix, value in
            switch prefix {
            case "b":
                return Undefined()
            case "e[f]":
                if let d = value as? Date {
                    return Int((d.timeIntervalSince1970 * 1000.0).rounded())
                }
            case "e[g][0]":
                if let n = value as? NSNumber { return n.intValue * 2 }
                if let i = value as? Int { return i * 2 }
            default: break
            }
            return value
        }
        let s = try Qs.encode(input, options: .init(encode: false, filter: filter))
        #expect(s == "a=b&c=d&e[f]=123&e[g][0]=4")
    }

    @Test("encode: filter with IterableFilter")
    func encode_filterIterable() throws {
        var s = try Qs.encode(
            ["a": "b", "c": "d", "e": "f"],
            options: .init(encode: false, filter: IterableFilter(["a", "e"]))
        )
        #expect(s == "a=b&e=f")

        s = try Qs.encode(
            ["a": ["b", "c", "d"], "e": "f"],
            options: .init(encode: false, filter: IterableFilter(["a", 0, 2]))
        )
        #expect(s == "a[0]=b&a[2]=d")
    }

    // MARK: - Null values

    @Test("nulls: treat null like empty string by default (encode)")
    func nulls_encodeDefaults() throws {
        let s = try Qs.encode(["a": NSNull(), "b": ""])
        #expect(s == "a=&b=")
    }

    @Test("nulls: decoding treats 'a&b=' as empty strings")
    func nulls_decodeEmptyStrings() throws {
        let r = try Qs.decode("a&b=")
        #expect((r["a"] as? String) == "")
        #expect((r["b"] as? String) == "")
    }

    @Test("nulls: strictNullHandling on encode")
    func nulls_encodeStrictNulls() throws {
        let s = try Qs.encode(["a": NSNull(), "b": ""], options: .init(strictNullHandling: true))
        #expect(s == "a&b=")
    }

    @Test("nulls: strictNullHandling on decode")
    func nulls_decodeStrictNulls() throws {
        let r = try Qs.decode("a&b=", options: .init(strictNullHandling: true))
        #expect(r["a"] is NSNull)
        #expect((r["b"] as? String) == "")
    }

    @Test("nulls: skipNulls on encode")
    func nulls_skipNulls() throws {
        let s = try Qs.encode(["a": "b", "c": NSNull()], options: .init(skipNulls: true))
        #expect(s == "a=b")
    }

    // MARK: - Charset (encoding)

    @Test("charset: encode using latin1")
    func charset_encodeLatin1() throws {
        let s = try Qs.encode(["æ": "æ"], options: .init(charset: .isoLatin1))
        #expect(s == "%E6=%E6")
    }

    @Test("charset: characters not in latin1 → numeric entities")
    func charset_numericEntitiesWhenNeeded() throws {
        let s = try Qs.encode(["a": "☺"], options: .init(charset: .isoLatin1))
        #expect(s == "a=%26%239786%3B")
    }

    @Test("charset: charsetSentinel with UTF-8")
    func charset_sentinelUtf8() throws {
        let s = try Qs.encode(["a": "☺"], options: .init(charsetSentinel: true))
        #expect(s == "utf8=%E2%9C%93&a=%E2%98%BA")
    }

    @Test("charset: charsetSentinel with latin1")
    func charset_sentinelLatin1() throws {
        let s = try Qs.encode(
            ["a": "æ"],
            options: .init(charset: .isoLatin1, charsetSentinel: true)
        )
        #expect(s == "utf8=%26%2310003%3B&a=%E6")
    }

    @Test("charset: custom encoder for different charsets (mock)")
    func charset_customEncoderMock() throws {
        let enc: ValueEncoder = { value, _, _ in
            // unwrap Any? → String (or fallback)
            let s: String
            if let v = value as? String {
                s = v
            } else if let v = value {
                s = String(describing: v)
            } else {
                s = ""
            }

            switch s {
            case "a": return "%61"
            case "hello": return "%68%65%6c%6c%6f"
            default: return s
            }
        }

        // (encodeValuesOnly is false by default, so keys go through the encoder too)
        let s = try Qs.encode(["a": "hello"], options: .init(encoder: enc))
        #expect(s == "%61=%68%65%6c%6c%6f")
    }

    @Test("charset: custom decoder for different charsets (mock)")
    func charset_customDecoderMock() throws {
        let dec: ValueDecoder = { str, _ in
            switch str {
            case "%61": return "a"
            case "%68%65%6c%6c%6f": return "hello"
            default: return str
            }
        }
        let r = try Qs.decode("%61=%68%65%6c%6c%6f", options: .init(decoder: dec))
        #expect((r["a"] as? String) == "hello")
    }

    // MARK: - RFC 3986 vs RFC 1738 space encoding

    @Test("spaces: RFC 3986 default → %20")
    func spaces_default3986() throws {
        #expect(try Qs.encode(["a": "b c"]) == "a=b%20c")
    }

    @Test("spaces: explicit RFC 3986")
    func spaces_explicit3986() throws {
        #expect(try Qs.encode(["a": "b c"], options: .init(format: .rfc3986)) == "a=b%20c")
    }

    @Test("spaces: RFC 1738 → +")
    func spaces_rfc1738() throws {
        #expect(try Qs.encode(["a": "b c"], options: .init(format: .rfc1738)) == "a=b+c")
    }
}

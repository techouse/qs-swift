import Foundation
import OrderedCollections

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct DecodeFastPathTests {
    @Test("flat fast-path parity: duplicates, strict null handling, and charset sentinel")
    func flatFastPath_parity() throws {
        let combined = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .combine))
        #expect(strings(combined["foo"]) == ["bar", "baz"])

        let first = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .first))
        #expect(first["foo"] as? String == "bar")

        let last = try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .last))
        #expect(last["foo"] as? String == "baz")

        let strict = try Qs.decode("a&b=", options: .init(strictNullHandling: true))
        #expect(strict["a"] is NSNull)
        #expect(strict["b"] as? String == "")

        let sentinel = try Qs.decode(
            "utf8=%E2%9C%93&a=%C3%B8",
            options: .init(charset: .isoLatin1, charsetSentinel: true)
        )
        #expect(sentinel["a"] as? String == "ø")
    }

    @Test("mixed flat/structured parity: root collisions and ordering")
    func mixedFastPath_parity() throws {
        let flatBeforeStructured = try Qs.decode("a=1&a[b]=2")
        let a1 = flatBeforeStructured["a"] as? [Any]
        #expect(a1?.count == 2)
        #expect(a1?.first as? String == "1")
        #expect((a1?[1] as? [String: Any])?["b"] as? String == "2")

        let structuredBeforeFlat = try Qs.decode("a[b]=2&a=1")
        #expect((structuredBeforeFlat["a"] as? [String: Any])?["b"] as? String == "2")

        let flatZeroThenArrayRoot = try Qs.decode("0=y&[]=x")
        #expect(flatZeroThenArrayRoot["0"] != nil)

        let arrayRootThenFlatZero = try Qs.decode("[]=x&0=y")
        #expect(strings(arrayRootThenFlatZero["0"]) == ["x", "y"])

        let allowDotsCollision = try Qs.decode("a=2&a.b=1", options: .init(allowDots: true))
        let a2 = allowDotsCollision["a"] as? [Any]
        #expect(a2?.count == 2)
        #expect(a2?.first as? String == "2")
        #expect((a2?[1] as? [String: Any])?["b"] as? String == "1")

        let encodedDotStructuredPlusFlat = try Qs.decode(
            "a%252Eb=1&a=2",
            options: .init(allowDots: true, decodeDotInKeys: true)
        )
        #expect(encodedDotStructuredPlusFlat["a.b"] as? String == "1")
        #expect(encodedDotStructuredPlusFlat["a"] as? String == "2")

        let leadingZeroNoCollision = try Qs.decode("[01]=x&1=y")
        #expect(leadingZeroNoCollision["01"] as? String == "x")
        #expect(leadingZeroNoCollision["1"] as? String == "y")

        let leadingZeroCollision = try Qs.decode("[01]=x&01=y")
        #expect(strings(leadingZeroCollision["01"]) == ["x", "y"])

        let leadingZeroCollisionReverse = try Qs.decode("01=y&[01]=x")
        #expect(strings(leadingZeroCollisionReverse["01"]) == ["y", "x"])
    }

    @Test("parameter-limit parity: raw token counting including empty and sentinel tokens")
    func parameterLimit_rawTokenParity() throws {
        let truncated = try Qs.decode("=x&=y&a=1", options: .init(parameterLimit: 1))
        #expect(truncated.isEmpty)

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
            _ = try Qs.decode("=x&=y&a=1", options: .init(parameterLimit: 1, throwOnLimitExceeded: true))
        }

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 2)) {
            _ = try Qs.decode("=x&=y&a=1", options: .init(parameterLimit: 2, throwOnLimitExceeded: true))
        }

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
            _ = try Qs.decode(
                "&&=ignored&&a=1&&",
                options: .init(parameterLimit: 1, throwOnLimitExceeded: true)
            )
        }

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
            _ = try Qs.decode(
                "utf8=%E2%9C%93&a=1",
                options: .init(
                    charset: .isoLatin1,
                    charsetSentinel: true,
                    parameterLimit: 1,
                    throwOnLimitExceeded: true
                )
            )
        }

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
            _ = try Qs.decode(
                "utf8=%E2%9C%93&a=1&b=2",
                options: .init(
                    charset: .isoLatin1,
                    charsetSentinel: true,
                    parameterLimit: 1,
                    throwOnLimitExceeded: true
                )
            )
        }

        let customDelimiterTruncated = try Qs.decode(
            ";;=ignored;;a=1;;",
            options: .init(
                delimiter: StringDelimiter(";"),
                parameterLimit: 1
            )
        )
        #expect(customDelimiterTruncated.isEmpty)

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
            _ = try Qs.decode(
                ";;=ignored;;a=1;;",
                options: .init(
                    delimiter: StringDelimiter(";"),
                    parameterLimit: 1,
                    throwOnLimitExceeded: true
                )
            )
        }

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 3)) {
            _ = try Qs.decode(
                "a=1,2&b=2&c=3&d=4",
                options: .init(
                    listLimit: 1,
                    comma: true,
                    parameterLimit: 3,
                    throwOnLimitExceeded: true
                )
            )
        }

        #expect(throws: DecodeError.parameterLimitExceeded(limit: 3)) {
            _ = try Qs.decode(
                "utf8=%E2%9C%93&a=1,2&b=2&c=3",
                options: .init(
                    listLimit: 1,
                    charset: .isoLatin1,
                    charsetSentinel: true,
                    comma: true,
                    parameterLimit: 3,
                    throwOnLimitExceeded: true
                )
            )
        }
    }

    @Test("top-level list-limit gate still counts empty-key pairs")
    func listLimit_gateCountsEmptyKeyPairs() throws {
        let decoded = try Qs.decode("=&a[]=b&a[]=c", options: .init(listLimit: 1))
        let forcedNoLists = try Qs.decode(
            "=&a[]=b&a[]=c",
            options: .init(listLimit: 1, parseLists: false)
        )
        #expect(NSDictionary(dictionary: decoded).isEqual(to: forcedNoLists))
        #expect(decoded[""] == nil)
    }

    @Test("string delimiter filtering preserves ]= split precedence")
    func stringDelimiterFiltering_preservesBracketEqualsSemantics() throws {
        let stringDelim = try Qs.decode("=x]=y")
        #expect(stringDelim["=x]"] as? String == "y")

        let regexDelim = try Qs.decode(
            "=x]=y",
            options: .init(delimiter: try RegexDelimiter("&"))
        )
        #expect(regexDelim["=x]"] as? String == "y")
    }

    @Test("parseQueryStringValues throws for empty string delimiter")
    func parseQuery_emptyStringDelimiter_throws() {
        #expect(throws: DecodeError.emptyDelimiter) {
            _ = try Decoder.parseQueryStringValues(
                "a=1",
                options: .init(delimiter: StringDelimiter(""), parameterLimit: 1)
            )
        }
    }

    @Test("empty bracket marker only comes from key context, not value content")
    func emptyBracketMarker_keyContextOnly() throws {
        let valueContainsMarker = try Qs.decode("a[b]=1,2[]=", options: .init(comma: true))
        let nested = valueContainsMarker["a"] as? [String: Any]
        #expect(strings(nested?["b"]) == ["1", "2[]="])

        for query in ["a[]=1,2", "a%5B]=1,2", "a[%5D=1,2", "a%5B%5D=1,2"] {
            let keyContainsMarker = try Qs.decode(query, options: .init(comma: true))
            let outer = keyContainsMarker["a"] as? [Any]
            #expect(outer?.count == 1, "query=\(query)")
            #expect(strings(outer?.first as Any?) == ["1", "2"], "query=\(query)")
        }
    }

    @Test("structured-scan helpers: split index, root extraction, and empty scan")
    func structuredScan_helpers() throws {
        let idx = Decoder.firstStructuredSplitIndex("a%2eb%2Ec", allowDots: true)
        #expect(idx == 1)

        let root1 = Decoder.leadingStructuredRoot("a[b]=1", options: .init())
        #expect(root1 == "a")

        let root2 = Decoder.leadingStructuredRoot("[]=x", options: .init())
        #expect(root2 == "0")

        let emptyScan = Decoder.scanStructuredKeys(OrderedDictionary<String, Any>(), options: .init())
        #expect(emptyScan.hasAnyStructuredSyntax == false)
        #expect(emptyScan.containsStructuredKey("a") == false)
        #expect(emptyScan.containsStructuredRoot("a") == false)

        let scan = Decoder.scanStructuredKeys(
            OrderedDictionary(
                uniqueKeysWithValues: [("a[b]", "1" as Any), ("plain", "2" as Any)]),
            options: .init()
        )
        #expect(scan.hasAnyStructuredSyntax)
        #expect(scan.containsStructuredKey("a[b]"))
        #expect(scan.containsStructuredRoot("a"))
        #expect(scan.containsStructuredRoot("plain") == false)
    }

    @Test("flat fast kernel matches legacy flat decode pipeline")
    func flatFastKernel_matchesLegacyFlatDecode() throws {
        let cases: [(String, DecodeOptions)] = [
            ("a=1&b=2&c=3", .init()),
            ("foo=bar+baz&x=%2B", .init()),
            ("a&b=", .init(strictNullHandling: true)),
            ("utf8=%E2%9C%93&a=%C3%B8", .init(charset: .isoLatin1, charsetSentinel: true)),
            ("k0=a,b,c&k1=x&k2=1,2,3", .init(comma: true)),
        ]

        for (query, options) in cases {
            guard let fast = try Decoder.decodeFlatQueryStringFast(query, options: options) else {
                Issue.record("Expected fast flat decode for query=\(query)")
                continue
            }
            let legacy = try legacyFlatDecode(query, options: options)
            #expect(
                NSDictionary(dictionary: fast).isEqual(to: legacy),
                "mismatch query=\(query)\nfast=\(fast)\nlegacy=\(legacy)"
            )
        }
    }

    @Test("flat fast kernel sentinel fallback preserves limits, duplicates, and empty-key stripping")
    func flatFastKernel_sentinelFallbackBranches() throws {
        #expect(throws: DecodeError.parameterLimitExceeded(limit: 1)) {
            _ = try Decoder.decodeFlatQueryStringFast(
                "a=1&utf8=%26%2310003%3B",
                options: .init(charsetSentinel: true, parameterLimit: 1, throwOnLimitExceeded: true)
            )
        }

        let duplicate = try Decoder.decodeFlatQueryStringFast(
            "a=1&utf8=%26%2310003%3B&a=2",
            options: .init(charsetSentinel: true)
        )
        #expect(duplicate == nil)

        let strippedEmptyKey = try Decoder.decodeFlatQueryStringFast(
            "=x&utf8=%E2%9C%93&a=1",
            options: .init(charsetSentinel: true)
        )
        let stripped = try #require(strippedEmptyKey)
        #expect(stripped[""] == nil)
        #expect(stripped["a"] as? String == "1")
    }

    @Test("flat fast kernel returns concrete comma lists on throwing success")
    func flatFastKernel_throwingCommaSuccess() throws {
        let decoded = try Decoder.decodeFlatQueryStringFast(
            "a=b,c",
            options: .init(listLimit: 2, comma: true, throwOnLimitExceeded: true)
        )
        let flat = try #require(decoded)

        #expect(strings(flat["a"]) == ["b", "c"])
    }

    @Test("flat fast kernel bails out for structured keys")
    func flatFastKernel_fallsBackOnStructuredSyntax() throws {
        #expect(try Decoder.decodeFlatQueryStringFast("a[b]=1", options: .init()) == nil)
        #expect(try Decoder.decodeFlatQueryStringFast("a%5Bb%5D=1", options: .init()) == nil)
        #expect(try Decoder.decodeFlatQueryStringFast("[]=x", options: .init()) == nil)
        #expect(try Decoder.decodeFlatQueryStringFast("a.b=1", options: .init(allowDots: true)) == nil)
        #expect(try Decoder.decodeFlatQueryStringFast("foo=bar&foo=baz", options: .init()) == nil)
        #expect(try Decoder.decodeFlatQueryStringFast("=x&=y&a=1", options: .init(parameterLimit: 3)) == nil)
    }

    @Test("flat fast kernel bails out when legacy decoder is configured")
    func flatFastKernel_fallsBackWhenLegacyDecoderIsConfigured() throws {
        @available(*, deprecated) typealias Legacy = LegacyDecoder
        let legacy: Legacy = { value, _ in
            let raw = value ?? "nil"
            return "legacy:\(raw)"
        }
        let options = DecodeOptions(legacyDecoder: legacy)

        #expect(try Decoder.decodeFlatQueryStringFast("foo=bar+baz", options: options) == nil)

        let decoded = try Qs.decode("foo=bar+baz", options: options)
        #expect(decoded["legacy:foo"] as? String == "bar baz")
    }

    @Test("flat fast kernel bails out for non-single-byte string delimiters")
    func flatFastKernel_fallsBackOnNonSingleByteDelimiter() throws {
        let combiningDelimiter = "e\u{301}"
        let combiningOptions = DecodeOptions(delimiter: StringDelimiter(combiningDelimiter))
        #expect(
            try Decoder.decodeFlatQueryStringFast(
                "a=1\(combiningDelimiter)b=2",
                options: combiningOptions
            ) == nil
        )
        let combiningDecoded = try Qs.decode("a=1\(combiningDelimiter)b=2", options: combiningOptions)
        #expect(combiningDecoded["a"] as? String == "1")
        #expect(combiningDecoded["b"] as? String == "2")

        let nonASCIIByteDelimiter = "é"
        let nonASCIIOptions = DecodeOptions(delimiter: StringDelimiter(nonASCIIByteDelimiter))
        #expect(
            try Decoder.decodeFlatQueryStringFast(
                "a=1\(nonASCIIByteDelimiter)b=2",
                options: nonASCIIOptions
            ) == nil
        )
        let nonASCIIDecoded = try Qs.decode("a=1\(nonASCIIByteDelimiter)b=2", options: nonASCIIOptions)
        #expect(nonASCIIDecoded["a"] as? String == "1")
        #expect(nonASCIIDecoded["b"] as? String == "2")
    }

    @Test("flat finalize path preserves already-concrete nested arrays and dictionaries")
    func flatFinalize_preservesConcreteNestedContainers() {
        let input: [String: Any] = [
            "list": [["inner": "value"], "tail"],
            "dict": ["nested": ["leaf": 1]],
        ]

        let finalized = Qs.finalizeFlatDecodedObject(input, options: .init(), dropDepth: 0)
        #expect(NSDictionary(dictionary: finalized).isEqual(to: input))
    }
}

private func strings(_ value: Any?) -> [String]? {
    if let arr = value as? [String] { return arr }
    if let arr = value as? [Any] {
        var out: [String] = []
        out.reserveCapacity(arr.count)
        for element in arr {
            guard let string = element as? String else { return nil }
            out.append(string)
        }
        return out
    }
    return nil
}

private func legacyFlatDecode(_ query: String, options: DecodeOptions) throws -> [String: Any] {
    let tmp = try Decoder.parseQueryStringValues(query, options: options)
    var flat: [String: Any] = [:]
    flat.reserveCapacity(tmp.count)
    for (key, value) in tmp where !key.isEmpty {
        flat[key] = value
    }
    return Qs.finalizeDecodedObject(flat, options: options, dropDepth: options.depth)
}

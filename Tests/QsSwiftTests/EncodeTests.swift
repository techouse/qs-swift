import Foundation
import OrderedCollections

@testable import QsSwift

#if canImport(Darwin)
    import CoreFoundation
#endif

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct EncodeTests {
    @Test("encode - encodes a simple Map to a query string")
    func testEncodeSimpleMapToQueryString() async throws {
        #expect(try Qs.encode(["a": "c"]) == "a=c")
    }

    @Test("encode - normalizes heterogeneous root containers")
    func encode_rootNormalizationVariants() async throws {
        var odNSString = OrderedDictionary<NSString, Any>()
        odNSString["one"] = 1
        odNSString["two"] = 2
        let orderedOutput = try Qs.encode(odNSString, options: EncodeOptions(encode: false))
        #expect(orderedOutput == "one=1&two=2")

        let dictAnyHashable: [AnyHashable: Any] = [1: "one", "two": 2]
        let sortedOutput = try Qs.encode(
            dictAnyHashable,
            options: EncodeOptions(
                encode: false,
                sort: { lhs, rhs in
                    let la = String(describing: lhs ?? "")
                    let lb = String(describing: rhs ?? "")
                    return la.compare(lb).rawValue
                }
            )
        )
        #expect(sortedOutput == "1=one&two=2")

        let nsDict: NSDictionary = ["gamma": "g", 5: "five"]
        let nsOutput = try Qs.encode(
            nsDict,
            options: EncodeOptions(
                encode: false,
                sort: { lhs, rhs in
                    let la = String(describing: lhs ?? "")
                    let lb = String(describing: rhs ?? "")
                    return la.compare(lb).rawValue
                }
            )
        )
        #expect(nsOutput == "5=five&gamma=g")

        let arrayOutput = try Qs.encode(["first", "second"], options: EncodeOptions(encode: false))
        #expect(arrayOutput == "0=first&1=second")
    }

    @Test("encode - function filter adopts OrderedDictionary root")
    func encode_functionFilterOrdersDictionary() async throws {
        let options = EncodeOptions(
            encode: false,
            filter: FunctionFilter { key, _ in
                guard key.isEmpty else { return nil }
                var ordered = OrderedDictionary<String, Any>()
                ordered["z"] = 1
                ordered["a"] = 2
                return ordered
            }
        )

        let result = try Qs.encode(["ignored": "value"], options: options)
        // Root adoption keeps OrderedDictionary ordering; values remain blank because NSNumber-backed Ints
        // stringify to "" when `encode` is disabled for this filter.
        #expect(result == "z=&a=")
    }

    @Test("encode - function filter adopts NSDictionary root")
    func encode_functionFilterNSDictionary() async throws {
        let options = EncodeOptions(
            encode: false,
            filter: FunctionFilter { key, _ in
                guard key.isEmpty else { return nil }
                return NSDictionary(dictionary: ["foo": "bar", "baz": 3])
            }
        )

        let result = try Qs.encode(["placeholder": 0], options: options)
        let parts = Set(result.split(separator: "&"))
        #expect(parts.contains { $0.hasPrefix("foo=") })
        #expect(parts.contains { $0.hasPrefix("baz=") })
    }

    @Test("encode - function filter adopts root array")
    func encode_functionFilterArrayReplacement() async throws {
        let options = EncodeOptions(
            encode: false,
            filter: FunctionFilter { key, _ in
                guard key.isEmpty else { return nil }
                return ["first", "second"]
            }
        )

        let result = try Qs.encode(["ignored": "x"], options: options)
        let parts = Set(result.split(separator: "&"))
        #expect(parts == Set(["0=", "1="]))
    }

    @Test("encode - iterable filter skips non-string keys safely")
    func encode_iterableFilterDropsNonStringKeys() async throws {
        let output = try Qs.encode(
            ["items": ["a", "b", "c"]],
            options: EncodeOptions(
                encode: false,
                filter: IterableFilter.indices(2, 0)
            )
        )

        #expect(output.isEmpty)
    }

    @Test("encode - function filter stringifies AnyHashable keys")
    func encode_functionFilterAnyHashableMap() async throws {
        let options = EncodeOptions(
            encode: false,
            filter: FunctionFilter { key, _ in
                guard key.isEmpty else { return nil }
                return [AnyHashable(1): "one", AnyHashable("two"): 2]
            }
        )

        let result = try Qs.encode(["placeholder": true], options: options)
        let parts = Set(result.split(separator: "&"))
        #expect(parts.contains { $0.hasPrefix("1=") })
        #expect(parts.contains { $0.hasPrefix("two=") })
    }

    @Test("encode - set-like scalars are preserved")
    func encode_setLikeScalarsArePreserved() async throws {
        let value = try Qs.encode(
            [
                "tags": Set(["red"]),
                "ordered": OrderedSet(["blue"]),
            ],
            options: EncodeOptions(encode: false)
        )

        let parts = Set(value.split(separator: "&").map(String.init))
        #expect(parts.contains { $0.hasPrefix("tags=") && $0 != "tags=" })
        #expect(parts.contains { $0.hasPrefix("ordered=") && $0 != "ordered=" })
    }

    @Test("encode - applies filters, ordering, and sentinel options")
    func encode_filtersOrderingAndSentinel() async throws {
        let data: [String: Any] = [
            "beta.key": ["list": ["x"]],
            "alpha": "A",
            "drop": "ignored",
            "nullish": NSNull(),
        ]

        let functionFilter = FunctionFilter { key, value in
            guard key.isEmpty, var dict = value as? [String: Any] else { return value }
            dict.removeValue(forKey: "drop")
            dict["gamma"] = "3"
            return dict
        }

        let opts = EncodeOptions(
            listFormat: .comma,
            allowDots: true,
            addQueryPrefix: true,
            allowEmptyLists: true,
            charset: .isoLatin1,
            charsetSentinel: true,
            delimiter: ";",
            encode: true,
            encodeDotInKeys: true,
            format: .rfc1738,
            filter: functionFilter,
            skipNulls: true,
            strictNullHandling: true,
            commaRoundTrip: true,
            sort: { lhs, rhs in
                let la = String(describing: lhs ?? "")
                let lb = String(describing: rhs ?? "")
                return la.compare(lb).rawValue
            }
        )

        let encoded = try Qs.encode(data, options: opts)
        #expect(encoded.hasPrefix("?utf8=%26%2310003%3B"))
        let printable = encoded.removingPercentEncoding ?? encoded
        #expect(printable.contains("alpha=A"))
        #expect(printable.contains("beta%2Ekey%2Elist[]=x"))
        #expect(printable.contains("gamma=3"))

        let iterableOutput = try Qs.encode(
            ["alpha": 1, "beta": 2, "gamma": 3],
            options: EncodeOptions(
                encode: false,
                filter: IterableFilter.mixed("gamma", "alpha"),
                skipNulls: true
            )
        )
        #expect(iterableOutput == "gamma=3&alpha=1")
    }

    @Test("encode - strict null handling, custom encoder, and comma round-trip")
    func encode_strictNullsAndCommaRoundTrip() async throws {
        let data: [String: Any?] = [
            "nilValue": nil,
            "null": NSNull(),
            "list": ["single"],
        ]

        let result = try Qs.encode(
            data,
            options: EncodeOptions(
                listFormat: .comma,
                allowEmptyLists: true,
                encode: false,
                skipNulls: false,
                strictNullHandling: true,
                commaRoundTrip: true
            )
        )
        #expect(result.contains("nilValue"))
        #expect(result.contains("null"))
        #expect(result.contains("list[]=single"))

        let custom = try Qs.encode(
            ["value": "v"],
            options: EncodeOptions(
                encoder: { value, _, _ in
                    if let s = value as? String { return "ENC:\(s)" }
                    return "ENC"
                },
                listFormat: nil,
                encode: true,
                encodeValuesOnly: true,
                format: .rfc3986
            )
        )
        #expect(custom == "value=ENC:v")
    }

    @Test("encode - Default parameter initializations in _encode method")
    func testDefaultParameterInitializations() async throws {
        // This test targets default initializations
        let result = try Qs.encode(
            ["a": "b"],
            options: EncodeOptions(
                // Force the code to use the default initializations
                listFormat: nil,
                format: .rfc3986,
                commaRoundTrip: nil
            )
        )
        #expect(result == "a=b")

        // Try another approach with a list to trigger the generateArrayPrefix default
        let result2 = try Qs.encode(
            ["a": ["b", "c"]],
            options: EncodeOptions(
                // Force the code to use the default initializations
                listFormat: nil,
                commaRoundTrip: nil
            )
        )
        #expect(result2 == "a%5B0%5D=b&a%5B1%5D=c")

        // Try with comma format to trigger the commaRoundTrip default
        let result3 = try Qs.encode(
            ["a": ["b", "c"]],
            options: EncodeOptions(
                listFormat: .comma,
                commaRoundTrip: nil
            )
        )
        #expect(result3 == "a=b%2Cc")
    }

    @Test("encode - Default DateTime serialization")
    func testDefaultDateTimeSerialization() async throws {
        // Parse 2023-01-01T00:00:00.001Z
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateTime = f.date(from: "2023-01-01T00:00:00.001Z")!

        // Default serialization (encode=false, dateSerializer=nil)
        let result = try Qs.encode(
            ["date": dateTime],
            options: EncodeOptions(
                dateSerializer: nil,
                encode: false
            )
        )
        #expect(result == "date=2023-01-01T00:00:00.001Z")

        // List of DateTimes with comma format
        let result2 = try Qs.encode(
            ["dates": [dateTime, dateTime]],
            options: EncodeOptions(
                dateSerializer: nil,
                listFormat: .comma,
                encode: false
            )
        )
        #expect(result2 == "dates=2023-01-01T00:00:00.001Z,2023-01-01T00:00:00.001Z")
    }

    @Test("encode - Access property of non-Map, non-Iterable object")
    func testAccessPropertyOfNonMapNonIterableObject() async throws {
        // Custom object that's neither a Map nor an Iterable
        let customObj = CustomObject("test")

        // Sanity check for the helper
        #expect((customObj["prop"] as? String) == "test")

        // Encoding a non-Map/Array object should produce an empty result (no crash)
        let result = try Qs.encode(customObj, options: EncodeOptions(encode: false))
        #expect(result.isEmpty)

        // Use a custom filter to access properties on non-Map values
        let filtered = try Qs.encode(
            ["obj": customObj],
            options: EncodeOptions(
                encode: false,
                filter: FunctionFilter { _, map in
                    guard let dict = map as? [String: Any] else { return map }
                    var out: [String: Any] = [:]
                    for (k, v) in dict {
                        if let c = v as? CustomObject {
                            out[k] = c["prop"]  // "test"
                        } else {
                            out[k] = v
                        }
                    }
                    return out
                }
            )
        )
        #expect(filtered.contains("obj=test"))
    }

    @Test("encode - encodes a query string map")
    func testEncodeQueryStringMap() async throws {
        #expect(try Qs.encode(["a": "b"]) == "a=b")
        #expect(try Qs.encode(["a": 1]) == "a=1")
        #expect(try Qs.encode(["a": 1, "b": 2]) == "a=1&b=2")
        #expect(try Qs.encode(["a": "A_Z"]) == "a=A_Z")
        #expect(try Qs.encode(["a": "€"]) == "a=%E2%82%AC")
        #expect(try Qs.encode(["a": ""]) == "a=%EE%80%80")
        #expect(try Qs.encode(["a": "א"]) == "a=%D7%90")
        #expect(try Qs.encode(["a": "𐐷"]) == "a=%F0%90%90%B7")
    }

    @Test("encode - encodes with default parameter values")
    func testEncodeWithDefaultParameterValues() async throws {
        // ListFormat.COMMA, commaRoundTrip default (false), encode=false
        let opts1 = EncodeOptions(listFormat: .comma, encode: false)
        #expect(try Qs.encode(["a": ["b"]], options: opts1) == "a=b")

        // Explicit commaRoundTrip = true appends [] to single-item lists
        let opts2 = EncodeOptions(listFormat: .comma, encode: false, commaRoundTrip: true)
        #expect(try Qs.encode(["a": ["b"]], options: opts2) == "a[]=b")
    }

    @Test("encode - encodes a list")
    func testEncodeList() async throws {
        #expect(try Qs.encode([1234]) == "0=1234")
        #expect(try Qs.encode(["lorem", 1234, "ipsum"]) == "0=lorem&1=1234&2=ipsum")
    }

    @Test("encode - encodes falsy values")
    func testEncodeFalsyValues() async throws {
        #expect(try Qs.encode([String: Any]()) == "")
        #expect(try Qs.encode(nil as Any?) == "")
        #expect(try Qs.encode(nil as Any?, options: EncodeOptions(strictNullHandling: true)) == "")
        #expect(try Qs.encode(false) == "")
        #expect(try Qs.encode(0) == "")
    }

    @Test("encode - encodes bigints with custom encoder")
    func testEncodeBigints() throws {
        let threeI64: Int64 = 3

        // Append "n" for integer-like values; otherwise defer to normal encoding.
        let encodeWithN: ValueEncoder = { value, _, _ in
            if let v = value as? Int {
                return "\(v)n"
            }
            if let v = value as? Int64 {
                return "\(v)n"
            }
            if let v = value as? UInt {
                return "\(v)n"
            }
            if let v = value as? NSNumber {
                #if canImport(Darwin)
                    if CFNumberIsFloatType(v) == false {
                        // Treat non-floating NSNumbers as integers (Apple platforms)
                        return "\(v.int64Value)n"
                    }
                #else
                    // On Linux (swift-corelibs-foundation), CoreFoundation helpers are unavailable.
                    // Consider the value "integer-like" if its Double form equals its Int64 form.
                    let d = v.doubleValue
                    let i = v.int64Value
                    if d.isFinite && d == Double(i) {
                        return "\(i)n"
                    }
                #endif
            }
            // Everything else: use default encoding without the "n" suffix
            return Utils.encode(value, charset: .utf8, format: .rfc3986)
        }

        // Baselines (no custom encoder)
        #expect(try Qs.encode(threeI64) == "")
        #expect(try Qs.encode([threeI64]) == "0=3")
        #expect(try Qs.encode(["a": threeI64]) == "a=3")

        // With custom encoder
        #expect(try Qs.encode([3], options: .init(encoder: encodeWithN)) == "0=3n")
        #expect(try Qs.encode(["a": 3], options: .init(encoder: encodeWithN)) == "a=3n")

        // Indexless, values-only case
        #expect(
            try Qs.encode(
                ["a": [threeI64]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true)
            ) == "a[]=3"
        )
        #expect(
            try Qs.encode(
                ["a": [threeI64]],
                options: EncodeOptions(
                    encoder: encodeWithN, listFormat: .brackets, encodeValuesOnly: true)
            ) == "a[]=3n"
        )
    }

    @Test("encode - dot in key with allowDots/encodeDotInKeys combinations")
    func testEncodeDotInKeyCombinations() async throws {
        // allowDots=false, encodeDotInKeys=false
        #expect(
            try Qs.encode(
                ["name.obj": ["first": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: false, encodeDotInKeys: false)
            ) == "name.obj%5Bfirst%5D=John&name.obj%5Blast%5D=Doe"
        )

        // allowDots=true, encodeDotInKeys=false
        #expect(
            try Qs.encode(
                ["name.obj": ["first": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: true, encodeDotInKeys: false)
            ) == "name.obj.first=John&name.obj.last=Doe"
        )

        // allowDots=false, encodeDotInKeys=true
        #expect(
            try Qs.encode(
                ["name.obj": ["first": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: false, encodeDotInKeys: true)
            ) == "name%252Eobj%5Bfirst%5D=John&name%252Eobj%5Blast%5D=Doe"
        )

        // allowDots=true, encodeDotInKeys=true
        #expect(
            try Qs.encode(
                ["name.obj": ["first": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: true, encodeDotInKeys: true)
            ) == "name%252Eobj.first=John&name%252Eobj.last=Doe"
        )

        // nested with allowDots=true, encodeDotInKeys=false
        #expect(
            try Qs.encode(
                ["name.obj.subobject": ["first.godly.name": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: true, encodeDotInKeys: false)
            ) == "name.obj.subobject.first.godly.name=John&name.obj.subobject.last=Doe"
        )

        // nested with allowDots=false, encodeDotInKeys=true
        #expect(
            try Qs.encode(
                ["name.obj.subobject": ["first.godly.name": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: false, encodeDotInKeys: true)
            )
                == "name%252Eobj%252Esubobject%5Bfirst.godly.name%5D=John&name%252Eobj%252Esubobject%5Blast%5D=Doe"
        )

        // nested with allowDots=true, encodeDotInKeys=true
        #expect(
            try Qs.encode(
                ["name.obj.subobject": ["first.godly.name": "John", "last": "Doe"]],
                options: EncodeOptions(allowDots: true, encodeDotInKeys: true)
            )
                == "name%252Eobj%252Esubobject.first%252Egodly%252Ename=John&name%252Eobj%252Esubobject.last=Doe"
        )
    }

    @Test("encode - encodeDotInKeys=true auto-sets allowDots when unspecified")
    func testEncodeDotInKeysAutoAllowDots() async throws {
        #expect(
            try Qs.encode(
                ["name.obj.subobject": ["first.godly.name": "John", "last": "Doe"]],
                options: EncodeOptions(encodeDotInKeys: true)
            )
                == "name%252Eobj%252Esubobject.first%252Egodly%252Ename=John&name%252Eobj%252Esubobject.last=Doe"
        )
    }

    @Test("encode - encodeDotInKeys with allowDots and encodeValuesOnly")
    func testEncodeDotInKeysWithEncodeValuesOnly() async throws {
        #expect(
            try Qs.encode(
                ["name.obj": ["first": "John", "last": "Doe"]],
                options: EncodeOptions(
                    allowDots: true, encodeDotInKeys: true, encodeValuesOnly: true)
            ) == "name%2Eobj.first=John&name%2Eobj.last=Doe"
        )

        #expect(
            try Qs.encode(
                ["name.obj.subobject": ["first.godly.name": "John", "last": "Doe"]],
                options: EncodeOptions(
                    allowDots: true, encodeDotInKeys: true, encodeValuesOnly: true)
            ) == "name%2Eobj%2Esubobject.first%2Egodly%2Ename=John&name%2Eobj%2Esubobject.last=Doe"
        )
    }

    @Test("encode - adds query prefix")
    func testAddsQueryPrefix() async throws {
        #expect(try Qs.encode(["a": "b"], options: EncodeOptions(addQueryPrefix: true)) == "?a=b")
    }

    @Test("encode - with query prefix, outputs blank string for empty map")
    func testQueryPrefixWithEmptyMap() async throws {
        #expect(try Qs.encode([String: Any](), options: EncodeOptions(addQueryPrefix: true)) == "")
    }

    @Test("encode - encodes nested falsy values")
    func testEncodesNestedFalsyValues() async throws {
        // null represented as NSNull()
        #expect(
            try Qs.encode(["a": ["b": ["c": NSNull()]]]) == "a%5Bb%5D%5Bc%5D="
        )
        #expect(
            try Qs.encode(
                ["a": ["b": ["c": NSNull()]]],
                options: EncodeOptions(strictNullHandling: true)
            ) == "a%5Bb%5D%5Bc%5D"
        )
        #expect(
            try Qs.encode(["a": ["b": ["c": false]]]) == "a%5Bb%5D%5Bc%5D=false"
        )
    }

    @Test("encode - encodes a nested map")
    func testEncodesNestedMap() async throws {
        #expect(try Qs.encode(["a": ["b": "c"]]) == "a%5Bb%5D=c")
        #expect(
            try Qs.encode(["a": ["b": ["c": ["d": "e"]]]])
                == "a%5Bb%5D%5Bc%5D%5Bd%5D=e"
        )
    }

    @Test("encode - encodes a nested map with dots notation")
    func testEncodesNestedMapWithDots() async throws {
        #expect(
            try Qs.encode(["a": ["b": "c"]], options: EncodeOptions(allowDots: true)) == "a.b=c"
        )
        #expect(
            try Qs.encode(["a": ["b": ["c": ["d": "e"]]]], options: EncodeOptions(allowDots: true))
                == "a.b.c.d=e"
        )
    }

    @Test("encode - encodes a list value (indices/brackets/comma)")
    func testEncodesListValueVariants() async throws {
        // INDICES
        #expect(
            try Qs.encode(["a": ["b", "c", "d"]], options: EncodeOptions(listFormat: .indices))
                == "a%5B0%5D=b&a%5B1%5D=c&a%5B2%5D=d"
        )
        // BRACKETS
        #expect(
            try Qs.encode(["a": ["b", "c", "d"]], options: EncodeOptions(listFormat: .brackets))
                == "a%5B%5D=b&a%5B%5D=c&a%5B%5D=d"
        )
        // COMMA
        #expect(
            try Qs.encode(["a": ["b", "c", "d"]], options: EncodeOptions(listFormat: .comma))
                == "a=b%2Cc%2Cd"
        )
        // COMMA + roundTrip (multiple items: same as above)
        #expect(
            try Qs.encode(
                ["a": ["b", "c", "d"]],
                options: EncodeOptions(listFormat: .comma, commaRoundTrip: true)
            ) == "a=b%2Cc%2Cd"
        )
        // Default (indices)
        #expect(try Qs.encode(["a": ["b", "c", "d"]]) == "a%5B0%5D=b&a%5B1%5D=c&a%5B2%5D=d")
    }

    @Test("encode - omits nulls when asked")
    func testOmitsNullsWhenAsked() async throws {
        #expect(
            try Qs.encode(["a": "b", "c": NSNull()], options: EncodeOptions(skipNulls: true))
                == "a=b"
        )
        #expect(
            try Qs.encode(
                ["a": ["b": "c", "d": NSNull()]],
                options: EncodeOptions(skipNulls: true)
            ) == "a%5Bb%5D=c"
        )
    }

    @Test("encode - omits list indices when asked")
    func testOmitsListIndicesWhenAsked() async throws {
        // If your options support `indices: false`
        #expect(
            try Qs.encode(["a": ["b", "c", "d"]], options: EncodeOptions(indices: false))
                == "a=b&a=c&a=d"
        )
        // If instead you have a repeat-style format, uncomment this and adjust ListFormat accordingly:
        // #expect(try Qs.encode(["a": ["b", "c", "d"]], options: EncodeOptions(listFormat: .repeat)) == "a=b&a=c&a=d")
    }

    @Test("encode - omits map key/value pair when value is empty list")
    func testOmitsPairWhenEmptyList() async throws {
        #expect(try Qs.encode(["a": [] as [String], "b": "zz"]) == "b=zz")
    }

    @Test("encode - empty list handling with allowEmptyLists")
    func testEmptyListAllowEmptyLists() async throws {
        // Default / allowEmptyLists = false
        #expect(
            try Qs.encode(
                ["a": [] as [String], "b": "zz"], options: EncodeOptions(allowEmptyLists: false))
                == "b=zz"
        )
        // allowEmptyLists = true
        #expect(
            try Qs.encode(
                ["a": [] as [String], "b": "zz"], options: EncodeOptions(allowEmptyLists: true))
                == "a[]&b=zz"
        )
    }

    @Test("encode - allowEmptyLists + strictNullHandling")
    func testAllowEmptyListsStrictNullHandling() async throws {
        #expect(
            try Qs.encode(
                ["testEmptyList": [] as [String]],
                options: EncodeOptions(allowEmptyLists: true, strictNullHandling: true)
            ) == "testEmptyList[]"
        )
    }

    @Test("encode - NSNull value with strictNullHandling renders key/value pair")
    func encode_NSNullWithStrictNullHandlingProducesPair() async throws {
        let payload: [String: Any?] = ["a": NSNull()]
        let out = try Qs.encode(payload, options: EncodeOptions(strictNullHandling: true))
        #expect(out == "a")
    }

    @Test("encode - nil value with strictNullHandling uses custom encoder when provided")
    func encode_nilWithStrictNullHandlingRespectsCustomEncoder() async throws {
        let payload: [String: Any?] = ["a": nil]
        let opts = EncodeOptions(
            encoder: { value, _, _ in
                guard let token = value as? String else { return "" }
                return "enc(\(token))"
            },
            strictNullHandling: true
        )
        let out = try Qs.encode(payload, options: opts)
        #expect(out == "enc(a)=")
    }

    // MARK: encodeValuesOnly: one item vs multiple items

    @Test("encode - non-list item with encodeValuesOnly")
    func testEncodeValuesOnlyNonList() async throws {
        #expect(
            try Qs.encode(
                ["a": "c"], options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a=c"
        )
        #expect(
            try Qs.encode(
                ["a": "c"], options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a=c"
        )
        #expect(
            try Qs.encode(
                ["a": "c"], options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c"
        )
        #expect(try Qs.encode(["a": "c"], options: EncodeOptions(encodeValuesOnly: true)) == "a=c")
    }

    @Test("encode - list with a single item with encodeValuesOnly")
    func testEncodeValuesOnlySingleItemList() async throws {
        #expect(
            try Qs.encode(
                ["a": ["c"]], options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=c"
        )
        #expect(
            try Qs.encode(
                ["a": ["c"]], options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=c"
        )
        #expect(
            try Qs.encode(
                ["a": ["c"]], options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c"
        )
        #expect(
            try Qs.encode(
                ["a": ["c"]],
                options: EncodeOptions(
                    listFormat: .comma, encodeValuesOnly: true, commaRoundTrip: true)
            ) == "a[]=c"
        )
        // Default list format with encodeValuesOnly
        #expect(
            try Qs.encode(["a": ["c"]], options: EncodeOptions(encodeValuesOnly: true))
                == "a[0]=c"
        )
    }

    @Test("encode - list with multiple items with encodeValuesOnly")
    func testEncodeValuesOnlyMultipleItemsList() async throws {
        #expect(
            try Qs.encode(
                ["a": ["c", "d"]],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=c&a[1]=d"
        )
        #expect(
            try Qs.encode(
                ["a": ["c", "d"]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=c&a[]=d"
        )
        #expect(
            try Qs.encode(
                ["a": ["c", "d"]],
                options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c,d"
        )
        #expect(
            try Qs.encode(
                ["a": ["c", "d"]],
                options: EncodeOptions(
                    listFormat: .comma, encodeValuesOnly: true, commaRoundTrip: true)
            ) == "a=c,d"
        )
        // Default list format with encodeValuesOnly
        #expect(
            try Qs.encode(["a": ["c", "d"]], options: EncodeOptions(encodeValuesOnly: true))
                == "a[0]=c&a[1]=d"
        )
    }

    @Test("encode - list with multiple items containing a comma")
    func testEncodeValuesOnlyMultipleItemsWithCommaInside() async throws {
        #expect(
            try Qs.encode(
                ["a": ["c,d", "e"]],
                options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c%2Cd,e"
        )
        #expect(
            try Qs.encode(["a": ["c,d", "e"]], options: EncodeOptions(listFormat: .comma))
                == "a=c%2Cd%2Ce"
        )
        #expect(
            try Qs.encode(
                ["a": ["c,d", "e"]],
                options: EncodeOptions(
                    listFormat: .comma, encodeValuesOnly: true, commaRoundTrip: true)
            ) == "a=c%2Cd,e"
        )
        #expect(
            try Qs.encode(
                ["a": ["c,d", "e"]],
                options: EncodeOptions(listFormat: .comma, commaRoundTrip: true)
            ) == "a=c%2Cd%2Ce"
        )
    }

    @Test("encode - encodes a nested list value with encodeValuesOnly")
    func testEncodesNestedListValue() async throws {
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true)
            ) == "a[b][0]=c&a[b][1]=d"
        )
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true)
            ) == "a[b][]=c&a[b][]=d"
        )
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true)
            ) == "a[b]=c,d"
        )
        // Default with encodeValuesOnly (indices)
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(encodeValuesOnly: true)
            ) == "a[b][0]=c&a[b][1]=d"
        )
    }

    @Test("encode - encodes comma and empty list values")
    func testEncodesCommaAndEmptyListValues() async throws {
        // encode=false (no percent-encoding)
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .indices, encode: false))
                == "a[0]=,&a[1]=&a[2]=c,d%"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .brackets, encode: false))
                == "a[]=,&a[]=&a[]=c,d%"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .comma, encode: false))
                == "a=,,,c,d%"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "a=,&a=&a=c,d%"
        )

        // encode=true, encodeValuesOnly=true
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .brackets, encode: true, encodeValuesOnly: true))
                == "a[]=%2C&a[]=&a[]=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .comma, encode: true, encodeValuesOnly: true))
                == "a=%2C,,c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .repeatKey, encode: true, encodeValuesOnly: true)
            )
                == "a=%2C&a=&a=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .indices, encode: true, encodeValuesOnly: true))
                == "a[0]=%2C&a[1]=&a[2]=c%2Cd%25"
        )

        // encode=true, encodeValuesOnly=false (default)
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .brackets, encode: true, encodeValuesOnly: false)
            )
                == "a%5B%5D=%2C&a%5B%5D=&a%5B%5D=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .comma, encode: true, encodeValuesOnly: false))
                == "a=%2C%2C%2Cc%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(
                    listFormat: .repeatKey, encode: true, encodeValuesOnly: false)
            )
                == "a=%2C&a=&a=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": [",", "", "c,d%"]],
                options: EncodeOptions(listFormat: .indices, encode: true, encodeValuesOnly: false))
                == "a%5B0%5D=%2C&a%5B1%5D=&a%5B2%5D=c%2Cd%25"
        )
    }

    @Test("encode - encodes comma and empty non-list values")
    func testEncodesCommaAndEmptyNonListValues() async throws {
        // encode=false (no percent-encoding)
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .indices, encode: false))
                == "a=,&b=&c=c,d%"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .brackets, encode: false))
                == "a=,&b=&c=c,d%"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .comma, encode: false))
                == "a=,&b=&c=c,d%"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "a=,&b=&c=c,d%"
        )

        // encode=true (values encoded)
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .brackets, encode: true, encodeValuesOnly: true))
                == "a=%2C&b=&c=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .comma, encode: true, encodeValuesOnly: true))
                == "a=%2C&b=&c=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .repeatKey, encode: true, encodeValuesOnly: true)
            )
                == "a=%2C&b=&c=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .indices, encode: true, encodeValuesOnly: false))
                == "a=%2C&b=&c=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .brackets, encode: true, encodeValuesOnly: false)
            )
                == "a=%2C&b=&c=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(listFormat: .comma, encode: true, encodeValuesOnly: false))
                == "a=%2C&b=&c=c%2Cd%25"
        )
        #expect(
            try Qs.encode(
                ["a": ",", "b": "", "c": "c,d%"],
                options: EncodeOptions(
                    listFormat: .repeatKey, encode: true, encodeValuesOnly: false)
            )
                == "a=%2C&b=&c=c%2Cd%25"
        )
    }

    @Test("encode - encodes a nested list value with dots notation")
    func testEncodesNestedListValueWithDots() async throws {
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(
                    listFormat: .indices, allowDots: true, encodeValuesOnly: true))
                == "a.b[0]=c&a.b[1]=d"
        )
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(
                    listFormat: .brackets, allowDots: true, encodeValuesOnly: true))
                == "a.b[]=c&a.b[]=d"
        )
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(listFormat: .comma, allowDots: true, encodeValuesOnly: true))
                == "a.b=c,d"
        )
        #expect(
            try Qs.encode(
                ["a": ["b": ["c", "d"]]],
                options: EncodeOptions(allowDots: true, encodeValuesOnly: true))
                == "a.b[0]=c&a.b[1]=d"
        )
    }

    @Test("encode - encodes a map inside a list")
    func testEncodesMapInsideList() async throws {
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0][b]=c"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a[b]=c"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[][b]=c"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(encodeValuesOnly: true))
                == "a[0][b]=c"
        )

        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0][b][c][0]=1"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a[b][c]=1"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[][b][c][]=1"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(encodeValuesOnly: true))
                == "a[0][b][c][0]=1"
        )
    }

    @Test("encode - encodes a list with mixed maps and primitives")
    func testEncodesListWithMixedMapsAndPrimitives() async throws {
        #expect(
            try Qs.encode(
                ["a": [["b": 1], 2, 3]],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0][b]=1&a[1]=2&a[2]=3"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": 1], 2, 3]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[][b]=1&a[]=2&a[]=3"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": 1], 2, 3]],
                options: EncodeOptions(encodeValuesOnly: true))
                == "a[0][b]=1&a[1]=2&a[2]=3"
        )
    }

    @Test("encode - encodes a map inside a list with dots notation")
    func testEncodesMapInsideListWithDots() async throws {
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(
                    listFormat: .indices, allowDots: true, encodeValuesOnly: true))
                == "a[0].b=c"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(
                    listFormat: .brackets, allowDots: true, encodeValuesOnly: true))
                == "a[].b=c"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(allowDots: true, encodeValuesOnly: true))
                == "a[0].b=c"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(
                    listFormat: .indices, allowDots: true, encodeValuesOnly: true))
                == "a[0].b.c[0]=1"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(
                    listFormat: .brackets, allowDots: true, encodeValuesOnly: true))
                == "a[].b.c[]=1"
        )
        #expect(
            try Qs.encode(
                ["a": [["b": ["c": [1]]]]],
                options: EncodeOptions(allowDots: true, encodeValuesOnly: true))
                == "a[0].b.c[0]=1"
        )
    }

    @Test("encode - does not omit map keys when indices = false")
    func testDoesNotOmitMapKeysWhenIndicesFalse() async throws {
        #expect(
            try Qs.encode(
                ["a": [["b": "c"]]],
                options: EncodeOptions(indices: false))
                == "a%5Bb%5D=c"
        )
    }

    @Test("encode - uses indices notation for lists when indices=true")
    func testUsesIndicesNotationWhenIndicesTrue() async throws {
        #expect(
            try Qs.encode(
                ["a": ["b", "c"]],
                options: EncodeOptions(indices: true))
                == "a%5B0%5D=b&a%5B1%5D=c"
        )
    }

    @Test("encode - uses indices notation for lists when no listFormat is specified")
    func testUsesIndicesNotationWhenNoListFormatSpecified() async throws {
        #expect(
            try Qs.encode(["a": ["b", "c"]])
                == "a%5B0%5D=b&a%5B1%5D=c"
        )
    }

    @Test("encode - uses indices notation for lists when listFormat=indices")
    func testUsesIndicesNotationWhenListFormatIndices() async throws {
        #expect(
            try Qs.encode(["a": ["b", "c"]], options: EncodeOptions(listFormat: .indices))
                == "a%5B0%5D=b&a%5B1%5D=c"
        )
    }

    @Test("encode - uses repeat notation for lists when listFormat=repeat")
    func testUsesRepeatNotationWhenListFormatRepeat() async throws {
        #expect(
            try Qs.encode(["a": ["b", "c"]], options: EncodeOptions(listFormat: .repeatKey))
                == "a=b&a=c"
        )
    }

    @Test("encode - uses brackets notation for lists when listFormat=brackets")
    func testUsesBracketsNotationWhenListFormatBrackets() async throws {
        #expect(
            try Qs.encode(["a": ["b", "c"]], options: EncodeOptions(listFormat: .brackets))
                == "a%5B%5D=b&a%5B%5D=c"
        )
    }

    @Test("encode - encodes a complicated map")
    func testEncodesComplicatedMap() async throws {
        #expect(
            try Qs.encode(["a": ["b": "c", "d": "e"]])
                == "a%5Bb%5D=c&a%5Bd%5D=e"
        )
    }

    @Test("encode - encodes an empty value")
    func testEncodesEmptyValue() async throws {
        #expect(try Qs.encode(["a": ""]) == "a=")

        #expect(
            try Qs.encode(["a": NSNull()], options: EncodeOptions(strictNullHandling: true))
                == "a"
        )

        #expect(
            try Qs.encode(["a": "", "b": ""])
                == "a=&b="
        )

        #expect(
            try Qs.encode(
                ["a": NSNull(), "b": ""], options: EncodeOptions(strictNullHandling: true))
                == "a&b="
        )

        #expect(
            try Qs.encode(["a": ["b": ""]])
                == "a%5Bb%5D="
        )

        #expect(
            try Qs.encode(["a": ["b": NSNull()]], options: EncodeOptions(strictNullHandling: true))
                == "a%5Bb%5D"
        )

        #expect(
            try Qs.encode(["a": ["b": NSNull()]], options: EncodeOptions(strictNullHandling: false))
                == "a%5Bb%5D="
        )
    }

    @Test("encode - empty list across formats: default parameters")
    func testEmptyListDefaultParameters() async throws {
        let data: [String: Any] = [
            "a": [] as [Any],
            "b": [NSNull()] as [Any],
            "c": "c",
        ]
        #expect(try Qs.encode(data, options: EncodeOptions(encode: false)) == "b[0]=&c=c")
    }

    @Test("encode - empty list across formats: listFormat default variants")
    func testEmptyList_ListFormatDefaultVariants() async throws {
        let data: [String: Any] = [
            "a": [] as [Any],
            "b": [NSNull()] as [Any],
            "c": "c",
        ]

        // INDICES
        #expect(
            try Qs.encode(data, options: EncodeOptions(listFormat: .indices, encode: false))
                == "b[0]=&c=c"
        )
        // BRACKETS
        #expect(
            try Qs.encode(data, options: EncodeOptions(listFormat: .brackets, encode: false))
                == "b[]=&c=c"
        )
        // REPEAT
        #expect(
            try Qs.encode(data, options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "b=&c=c"
        )
        // COMMA
        #expect(
            try Qs.encode(data, options: EncodeOptions(listFormat: .comma, encode: false))
                == "b=&c=c"
        )
        // COMMA + roundTrip (single-item list -> brackets semantics)
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(listFormat: .comma, encode: false, commaRoundTrip: true)
            ) == "b[]=&c=c"
        )
    }

    @Test("encode - empty list with strictNullHandling across formats")
    func testEmptyList_StrictNullHandling() async throws {
        let data: [String: Any] = [
            "a": [] as [Any],
            "b": [NSNull()] as [Any],
            "c": "c",
        ]

        // BRACKETS
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(
                    listFormat: .brackets, encode: false, strictNullHandling: true
                )
            ) == "b[]&c=c"
        )
        // REPEAT
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(
                    listFormat: .repeatKey, encode: false, strictNullHandling: true
                )
            ) == "b&c=c"
        )
        // COMMA
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(
                    listFormat: .comma, encode: false, strictNullHandling: true
                )
            ) == "b&c=c"
        )
        // COMMA + roundTrip
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(
                    listFormat: .comma, encode: false, strictNullHandling: true,
                    commaRoundTrip: true
                )
            ) == "b[]&c=c"
        )
    }

    @Test("encode - empty list with skipNulls across formats")
    func testEmptyList_SkipNulls() async throws {
        let data: [String: Any] = [
            "a": [] as [Any],
            "b": [NSNull()] as [Any],
            "c": "c",
        ]

        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(listFormat: .indices, encode: false, skipNulls: true)
            ) == "c=c"
        )
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(listFormat: .brackets, encode: false, skipNulls: true)
            ) == "c=c"
        )
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(listFormat: .repeatKey, encode: false, skipNulls: true)
            ) == "c=c"
        )
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(listFormat: .comma, encode: false, skipNulls: true)
            ) == "c=c"
        )
    }

    @Test("encode - encodes a null map")
    func testEncodesNullMap() async throws {
        var obj: [String: Any?] = [:]
        obj["a"] = "b"
        #expect(try Qs.encode(obj) == "a=b")
    }

    @Test("encode - returns an empty string for invalid input")
    func testReturnsEmptyStringForInvalidInput() async throws {
        #expect(try Qs.encode(nil as Any?) == "")
        #expect(try Qs.encode(false) == "")
        #expect(try Qs.encode("") == "")
    }

    @Test("encode - encodes a map with a null map as a child")
    func testEncodesMapWithNullChildMap() async throws {
        var obj: [String: Any] = ["a": [String: Any]()]
        var child = obj["a"] as? [String: Any] ?? [:]
        child["b"] = "c"
        obj["a"] = child
        #expect(try Qs.encode(obj) == "a%5Bb%5D=c")
    }

    @Test("encode - url encodes values")
    func testUrlEncodesValues() async throws {
        #expect(try Qs.encode(["a": "b c"]) == "a=b%20c")
    }

    @Test("encode - encodes a date using default serializer")
    func testEncodesDate() async throws {
        // Build ISO8601 with fractional seconds (matches default serializer used elsewhere in tests)
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = iso.string(from: now)
        let expected = "a=" + Utils.encode(dateString, charset: .utf8, format: .rfc3986)
        #expect(try Qs.encode(["a": now]) == expected)
    }

    @Test("encode - encodes the weird map from qs")
    func testEncodesWeirdMapFromQs() async throws {
        #expect(
            try Qs.encode(["my weird field": "~q1!2\"'w$5&7/z8)?"])
                == "my%20weird%20field=~q1%212%22%27w%245%267%2Fz8%29%3F"
        )
    }

    @Test("encode - encodes boolean values")
    func testEncodesBooleanValues() async throws {
        #expect(try Qs.encode(["a": true]) == "a=true")
        let qs1 = try Qs.encode(["a": ["b": true]])
        #expect(qs1 == "a%5Bb%5D=true")
        #expect(try Qs.encode(["b": false]) == "b=false")
        let qs2 = try Qs.encode(["b": ["c": false]])
        #expect(qs2 == "b%5Bc%5D=false")
    }

    @Test("encode - encodes buffer (Data) values")
    func testEncodesBufferValues() async throws {
        let buf = "test".data(using: .utf8)!
        #expect(try Qs.encode(["a": buf]) == "a=test")
        #expect(try Qs.encode(["a": ["b": buf]]) == "a%5Bb%5D=test")
    }

    @Test("encode - encodes a map using an alternative delimiter")
    func testEncodesMapUsingAlternativeDelimiter() async throws {
        #expect(
            try Qs.encode(["a": "b", "c": "d"], options: EncodeOptions(delimiter: ";"))
                == "a=b;c=d"
        )
    }

    @Test("encode - non-circular duplicated references do not crash")
    func testNonCircularDuplicatedReferences() async throws {
        let hourOfDay: [String: Any] = ["function": "hour_of_day"]
        let p1: [String: Any] = ["function": "gte", "arguments": [hourOfDay, 0]]
        let p2: [String: Any] = ["function": "lte", "arguments": [hourOfDay, 23]]

        // indices
        #expect(
            try Qs.encode(
                ["filters": ["$and": [p1, p2]]],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true)
            )
                == "filters[$and][0][function]=gte&filters[$and][0][arguments][0][function]=hour_of_day&filters[$and][0][arguments][1]=0&filters[$and][1][function]=lte&filters[$and][1][arguments][0][function]=hour_of_day&filters[$and][1][arguments][1]=23"
        )
        // brackets
        #expect(
            try Qs.encode(
                ["filters": ["$and": [p1, p2]]],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true)
            )
                == "filters[$and][][function]=gte&filters[$and][][arguments][][function]=hour_of_day&filters[$and][][arguments][]=0&filters[$and][][function]=lte&filters[$and][][arguments][][function]=hour_of_day&filters[$and][][arguments][]=23"
        )
        // repeat
        #expect(
            try Qs.encode(
                ["filters": ["$and": [p1, p2]]],
                options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true)
            )
                == "filters[$and][function]=gte&filters[$and][arguments][function]=hour_of_day&filters[$and][arguments]=0&filters[$and][function]=lte&filters[$and][arguments][function]=hour_of_day&filters[$and][arguments]=23"
        )
    }

    @Test("encode - selects properties when filter = IterableFilter")
    func testIterableFilterSelection() async throws {
        // Only "a"
        #expect(
            try Qs.encode(["a": "b"], options: EncodeOptions(filter: IterableFilter(["a"])))
                == "a=b"
        )
        // Empty iterable -> nothing
        #expect(
            try Qs.encode(["a": 1], options: EncodeOptions(filter: IterableFilter([Any]())))
                == ""
        )

        // Nested, pick a.b[0] and a.b[2]
        let data: [String: Any] = ["a": ["b": [1, 2, 3, 4], "c": "d"], "c": "f"]
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(
                    listFormat: .indices,
                    filter: IterableFilter(["a", "b", 0, 2])
                )
            ) == "a%5Bb%5D%5B0%5D=1&a%5Bb%5D%5B2%5D=3"
        )
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(
                    listFormat: .brackets, filter: IterableFilter(["a", "b", 0, 2])
                )
            ) == "a%5Bb%5D%5B%5D=1&a%5Bb%5D%5B%5D=3"
        )
        #expect(
            try Qs.encode(
                data,
                options: EncodeOptions(filter: IterableFilter(["a", "b", 0, 2]))
            ) == "a%5Bb%5D%5B0%5D=1&a%5Bb%5D%5B2%5D=3"
        )
    }

    @Test("encode - IterableFilter keeps array indices type-strict")
    func encode_iterableFilterArrayIndicesAreTypeStrict() async throws {
        let result = try Qs.encode(
            ["a": [1, 2, 3]],
            options: EncodeOptions(
                encode: false,
                filter: IterableFilter(["a", "0", 2])
            )
        )

        #expect(result == "a[2]=3")
    }

    @Test("encode - supports custom representations when filter = FunctionFilter")
    func testFunctionFilterCustomRepresentations() async throws {
        var calls = 0
        // e.f = 2009-11-10T23:00:00Z
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: .gregorian)
        dateComponents.timeZone = TimeZone(secondsFromGMT: 0)
        dateComponents.year = 2009
        dateComponents.month = 11
        dateComponents.day = 10
        dateComponents.hour = 23
        dateComponents.minute = 0
        dateComponents.second = 0
        let date = dateComponents.date!
        let obj: [String: Any] = ["a": "b", "c": "d", "e": ["f": date]]

        let filter = FunctionFilter { prefix, value in
            calls += 1
            if prefix == "c" {
                return nil  // drop key "c"
            }
            if let d = value as? Date {
                // epoch millis
                return Int64(d.timeIntervalSince1970 * 1000.0)
            }
            return value
        }

        let out = try Qs.encode(obj, options: EncodeOptions(filter: filter))
        #expect(out == "a=b&c=&e%5Bf%5D=1257894000000")
        #expect(calls > 0)
    }

    @Test("encode - can disable uri encoding")
    func testCanDisableUriEncoding() async throws {
        #expect(try Qs.encode(["a": "b"], options: EncodeOptions(encode: false)) == "a=b")
        #expect(try Qs.encode(["a": ["b": "c"]], options: EncodeOptions(encode: false)) == "a[b]=c")
        #expect(
            try Qs.encode(
                ["a": "b", "c": NSNull()],
                options: EncodeOptions(encode: false, strictNullHandling: true))
                == "a=b&c"
        )
    }

    @Test("encode - can sort the keys")
    func testCanSortKeys() async throws {
        let sort: Sorter = { a, b in
            let as_ = String(describing: a ?? "")
            let bs_ = String(describing: b ?? "")
            if as_ == bs_ { return 0 }
            return as_ < bs_ ? -1 : 1
        }

        #expect(
            try Qs.encode(["a": "c", "z": "y", "b": "f"], options: EncodeOptions(sort: sort))
                == "a=c&b=f&z=y"
        )

        #expect(
            try Qs.encode(
                ["a": "c", "z": ["j": "a", "i": "b"], "b": "f"],
                options: EncodeOptions(sort: sort)
            ) == "a=c&b=f&z%5Bi%5D=b&z%5Bj%5D=a"
        )
    }

    @Test("Encoder.encode: NSDictionary + custom Sorter (mixed key types)")
    func nsdictionary_mixed_keys_custom_sort() throws {
        // Mix NSString and NSNumber keys so it cannot bridge to [String: Any]
        let nd: NSDictionary = [
            3: "three",
            "b": "2",
            "a": "1",
        ]

        // Sort by String(describing:) ascending
        let sorter: Sorter = { a, b in
            let sa = a.map { String(describing: $0) } ?? ""
            let sb = b.map { String(describing: $0) } ?? ""
            return sa.compare(sb).rawValue
        }

        // encode=false to keep brackets readable (no %5B/%5D)
        let out = try Qs.encode(["outer": nd], options: .init(encode: false, sort: sorter))

        // "3" < "a" < "b"
        #expect(out == "outer[3]=three&outer[a]=1&outer[b]=2")
    }

    @Test(
        "Encoder.encode: NSDictionary depth>0 (encoder != nil) partitions primitives before containers"
    )
    func nsdictionary_depth_encoder_partitions() throws {
        // 'a' and 'd' are primitives; 'b' and 'c' are containers
        let nd: NSDictionary = [
            "d": 0,
            "b": ["x": 1],
            "a": 1,
            "c": ["y": 2],
        ]

        // encode=true → encoder != nil so the partitioning path runs
        let out = try Qs.encode(["outer": nd], options: .init(encode: true))

        // Expect primitives ("a","d") sorted A..Z first, then containers ("b","c") sorted A..Z
        // (Percent-encoded brackets because encode=true)
        #expect(out == "outer%5Ba%5D=1&outer%5Bd%5D=0&outer%5Bb%5D%5Bx%5D=1&outer%5Bc%5D%5By%5D=2")
    }

    @Test(
        "Encoder.encode: NSDictionary depth>0 (encoder == nil) uses lexicographic fallback (order-insensitive)"
    )
    func nsdictionary_depth_no_encoder_lex_fallback() throws {
        // Force NSDictionary path (include a non-String key)
        let nd: NSDictionary = [
            "": [2, 3],  // empty key → produces "[]"
            "a": 2,
            1: 9,  // NSNumber key → will serialize as "[1]" at this depth
        ]

        let side = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()

        let any = try Encoder.encode(
            data: nd,
            undefined: false,
            sideChannel: side,
            prefix: "",  // depth>0 with empty prefix
            generateArrayPrefix: ListFormat.indices.generator,
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,  // encoder == nil → lexicographic fallback path
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 1
        )

        let s =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)

        // Order-insensitive check (we just care that lexicographic fallback ran)
        let parts = Set(s.split(separator: "&").map(String.init))
        let expected: Set<String> = ["[][0]=2", "[][1]=3", "[a]=2", "[1]=9"]
        #expect(parts == expected)
    }

    @Test("encode preserves OrderedDictionary insertion order (nested)")
    func encode_preservesOrderedDictionaryOrder_nested() throws {
        // Build nested ordered maps
        var zj: OrderedDictionary<String, Any> = [:]
        zj["zjb"] = "zjb"
        zj["zja"] = "zja"

        var zi: OrderedDictionary<String, Any> = [:]
        zi["zib"] = "zib"
        zi["zia"] = "zia"

        var z: OrderedDictionary<String, Any> = [:]
        z["zj"] = zj
        z["zi"] = zi

        var input: OrderedDictionary<String, Any> = [:]
        input["a"] = "a"
        input["z"] = z
        input["b"] = "b"

        // encode=false ⇒ no sorting; should respect insertion order
        let s = try Qs.encode(input, options: .init(encode: false))
        #expect(s == "a=a&z[zj][zjb]=zjb&z[zj][zja]=zja&z[zi][zib]=zib&z[zi][zia]=zia&b=b")
    }

    @Test("encode preserves nested OrderedDictionary order even with plain top-level map")
    func encode_preservesNestedOrder_withPlainTopLevel() throws {
        var zj: OrderedDictionary<String, Any> = [:]
        zj["zjb"] = "zjb"
        zj["zja"] = "zja"

        var zi: OrderedDictionary<String, Any> = [:]
        zi["zib"] = "zib"
        zi["zia"] = "zia"

        var z: OrderedDictionary<String, Any> = [:]
        z["zj"] = zj
        z["zi"] = zi

        // Top-level is a plain Dictionary; inner levels are OrderedDictionary
        let input: [String: Any] = ["a": "a", "z": z, "b": "b"]

        let s = try Qs.encode(input, options: .init(encode: false))
        // Top-level order may vary since Dictionary is unordered; but nested order must hold.
        // So just assert the nested segments are in order:
        #expect(s.contains("z[zj][zjb]=zjb&z[zj][zja]=zja"))
        #expect(s.contains("z[zi][zib]=zib&z[zi][zia]=zia"))
    }

    @Test("encode - can encode with custom encoding (Shift_JIS)")
    func testCanEncodeWithCustomEncoding_ShiftJIS() async throws {
        let custom: ValueEncoder = { value, _, _ in
            guard let s = value.map({ String(describing: $0) }), !s.isEmpty else { return "" }
            // Shift_JIS bytes -> %hh (lowercase)
            if let data = s.data(using: .shiftJIS) {
                return data.map { String(format: "%%%02x", $0) }.joined()
            }
            return ""
        }

        #if os(Linux)
            let supportsShiftJIS = "大阪府".data(using: .shiftJIS) != nil
            if supportsShiftJIS {
                #expect(
                    try Qs.encode(["県": "大阪府", "": ""], options: EncodeOptions(encoder: custom))
                        == "%8c%a7=%91%e5%8d%e3%95%7b&="
                )
            } else {
                try withKnownIssue {
                    let produced =
                        (try? Qs.encode(
                            ["県": "大阪府", "": ""],
                            options: EncodeOptions(encoder: custom))) ?? ""
                    #expect(produced == "%8c%a7=%91%e5%8d%e3%95%7b&=")
                }
            }
        #else
            #expect(
                try Qs.encode(["県": "大阪府", "": ""], options: EncodeOptions(encoder: custom))
                    == "%8c%a7=%91%e5%8d%e3%95%7b&="
            )
        #endif
    }

    @Test("encode - receives the default encoder as a second argument")
    func testReceivesDefaultEncoderAsSecondArgument() throws {
        let obj: [String: Any] = ["a": 1, "b": Date(), "c": true, "d": [1]]

        let recorder = _Recorder()

        let enc: ValueEncoder = { value, _, _ in
            switch value {
            case is String, is Int, is Bool:
                break  // allowed
            default:
                if let v = value {
                    recorder.add(String(describing: type(of: v)))
                } else {
                    recorder.add("nil")
                }
            }
            return ""
        }

        _ = try Qs.encode(obj, options: EncodeOptions(encoder: enc))

        // Fail the test if the encoder ever saw an unexpected type.
        #expect(recorder.isEmpty)
    }

    @Test("encode - can use custom encoder for a buffer map")
    func testCustomEncoderForBufferMap() async throws {
        // a single byte -> 'b'
        let buf = Data([1])
        let encode1: ValueEncoder = { buffer, _, _ in
            if let s = buffer as? String { return s }
            if let data = buffer as? Data {
                let first = data.first ?? 0
                return String(UnicodeScalar(97 + Int(first))!)
            }
            return buffer.map { String(describing: $0) } ?? ""
        }
        #expect(try Qs.encode(["a": buf], options: EncodeOptions(encoder: encode1)) == "a=b")

        // bytes -> UTF-8 text "a b"
        let bufferWithText = "a b".data(using: .utf8)!
        let encode2: ValueEncoder = { buffer, _, _ in
            if let data = buffer as? Data { return String(data: data, encoding: .utf8) ?? "" }
            return buffer.map { String(describing: $0) } ?? ""
        }
        #expect(
            try Qs.encode(["a": bufferWithText], options: EncodeOptions(encoder: encode2))
                == "a=a b")
    }

    @Test("encode - serializeDate option")
    func testSerializeDateOption() async throws {
        let date = Date()

        // Default behavior: encode(dateString) where dateString is default-serialized date
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = f.string(from: date)
        #expect(
            try Qs.encode(["a": date])
                == "a=\(Utils.encode(dateString, charset: .utf8, format: .rfc3986))")

        // Custom date serializer: epoch millis (system default tz doesn't affect epoch)
        let serializeDate: DateSerializer = { d in
            String(Int64(d.timeIntervalSince1970 * 1000))
        }
        #expect(
            try Qs.encode(["a": date], options: EncodeOptions(dateSerializer: serializeDate))
                == "a=\(Int64(date.timeIntervalSince1970 * 1000))"
        )

        // Specific date: epoch=6 -> custom serializer multiplies by 7 => 42
        let specificDate = Date(timeIntervalSince1970: 0.006)
        let customSerializeDate: DateSerializer = { d in
            String(Int64(d.timeIntervalSince1970 * 1000) * 7)
        }
        #expect(
            try Qs.encode(
                ["a": specificDate], options: EncodeOptions(dateSerializer: customSerializeDate))
                == "a=42"
        )

        // List with COMMA format
        #expect(
            try Qs.encode(
                ["a": [date]],
                options: EncodeOptions(dateSerializer: serializeDate, listFormat: .comma)
            ) == "a=\(Int64(date.timeIntervalSince1970 * 1000))"
        )
        // List with COMMA + commaRoundTrip=true => brackets for single-item list
        #expect(
            try Qs.encode(
                ["a": [date]],
                options: EncodeOptions(
                    dateSerializer: serializeDate, listFormat: .comma, commaRoundTrip: true)
            ) == "a%5B%5D=\(Int64(date.timeIntervalSince1970 * 1000))"
        )
    }

    @Test("encode - RFC 1738 serialization")
    func testRFC1738Serialization() async throws {
        #expect(try Qs.encode(["a": "b c"], options: EncodeOptions(format: .rfc1738)) == "a=b+c")
        #expect(
            try Qs.encode(["a b": "c d"], options: EncodeOptions(format: .rfc1738)) == "a+b=c+d")
        #expect(
            try Qs.encode(
                ["a b": "a b".data(using: .utf8)!], options: EncodeOptions(format: .rfc1738))
                == "a+b=a+b"
        )
        #expect(
            try Qs.encode(["foo(ref)": "bar"], options: EncodeOptions(format: .rfc1738))
                == "foo(ref)=bar")
    }

    @Test("encode - RFC 3986 spaces serialization")
    func testRFC3986SpacesSerialization() async throws {
        #expect(try Qs.encode(["a": "b c"], options: EncodeOptions(format: .rfc3986)) == "a=b%20c")
        #expect(
            try Qs.encode(["a b": "c d"], options: EncodeOptions(format: .rfc3986)) == "a%20b=c%20d"
        )
        #expect(
            try Qs.encode(
                ["a b": "a b".data(using: .utf8)!], options: EncodeOptions(format: .rfc3986))
                == "a%20b=a%20b"
        )
    }

    @Test("encode - Backward compatibility to RFC 3986")
    func testBackwardCompatibilityRFC3986() async throws {
        // Default format should behave like RFC3986
        #expect(try Qs.encode(["a": "b c"]) == "a=b%20c")
        #expect(try Qs.encode(["a b": "a b".data(using: .utf8)!]) == "a%20b=a%20b")
    }

    @Test("encode - encodeValuesOnly variants")
    func testEncodeValuesOnlyVariants() async throws {
        let input: [String: Any] = [
            "a": "b",
            "c": ["d", "e=f"],
            "f": [["g"], ["h"]],
        ]

        // encodeValuesOnly + indices
        #expect(
            try Qs.encode(
                input, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a=b&c[0]=d&c[1]=e%3Df&f[0][0]=g&f[1][0]=h"
        )
        // encodeValuesOnly + brackets
        #expect(
            try Qs.encode(
                input, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a=b&c[]=d&c[]=e%3Df&f[][]=g&f[][]=h"
        )
        // encodeValuesOnly + repeat
        #expect(
            try Qs.encode(
                input, options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a=b&c=d&c=e%3Df&f=g&f=h"
        )

        // No encodeValuesOnly, indices
        let input2: [String: Any] = [
            "a": "b",
            "c": ["d", "e"],
            "f": [["g"], ["h"]],
        ]
        #expect(
            try Qs.encode(input2, options: EncodeOptions(listFormat: .indices))
                == "a=b&c%5B0%5D=d&c%5B1%5D=e&f%5B0%5D%5B0%5D=g&f%5B1%5D%5B0%5D=h"
        )
        // No encodeValuesOnly, brackets
        #expect(
            try Qs.encode(input2, options: EncodeOptions(listFormat: .brackets))
                == "a=b&c%5B%5D=d&c%5B%5D=e&f%5B%5D%5B%5D=g&f%5B%5D%5B%5D=h"
        )
        // No encodeValuesOnly, repeat
        #expect(
            try Qs.encode(input2, options: EncodeOptions(listFormat: .repeatKey))
                == "a=b&c=d&c=e&f=g&f=h"
        )
    }

    @Test("encode - encodeValuesOnly with strictNullHandling")
    func testEncodeValuesOnlyStrictNullHandling() async throws {
        #expect(
            try Qs.encode(
                ["a": ["b": NSNull()]],
                options: EncodeOptions(encodeValuesOnly: true, strictNullHandling: true)
            ) == "a[b]"
        )
    }

    @Test("encode - respects a charset of iso-8859-1")
    func testRespectsCharsetIsoLatin() async throws {
        #expect(try Qs.encode(["æ": "æ"], options: EncodeOptions(charset: .isoLatin1)) == "%E6=%E6")
    }

    @Test("encode - encodes unrepresentable chars as numeric entities in iso-8859-1 mode")
    func testEncodesUnrepresentableInIsoLatin() async throws {
        #expect(
            try Qs.encode(["a": "☺"], options: EncodeOptions(charset: .isoLatin1))
                == "a=%26%239786%3B")
    }

    @Test("encode - respects an explicit charset of utf-8 (default)")
    func testRespectsExplicitCharsetUtf8() async throws {
        #expect(try Qs.encode(["a": "æ"], options: EncodeOptions(charset: .utf8)) == "a=%C3%A6")
    }

    @Test("encode - charsetSentinel option")
    func testCharsetSentinelOption() async throws {
        #expect(
            try Qs.encode(["a": "æ"], options: EncodeOptions(charset: .utf8, charsetSentinel: true))
                == "utf8=%E2%9C%93&a=%C3%A6"
        )
        #expect(
            try Qs.encode(
                ["a": "æ"], options: EncodeOptions(charset: .isoLatin1, charsetSentinel: true))
                == "utf8=%26%2310003%3B&a=%E6"
        )
    }

    @Test("encode - does not mutate the options argument")
    func testDoesNotMutateOptionsArgument() async throws {
        let options = EncodeOptions()
        _ = try Qs.encode([String: Any](), options: options)
        // If options mutated internally, subsequent encodes with the same instance would differ from a fresh one.
        let out1 = try Qs.encode(["x": "y"], options: options)
        let out2 = try Qs.encode(["x": "y"], options: EncodeOptions())
        #expect(out1 == out2)
    }

    @Test("encode - strictNullHandling works with custom filter")
    func testStrictNullHandlingWithCustomFilter() async throws {
        let options = EncodeOptions(
            filter: FunctionFilter { _, value in value }, strictNullHandling: true
        )
        #expect(try Qs.encode(["key": NSNull()], options: options) == "key")
    }

    @Test("encode - objects inside lists")
    func testObjectsInsideLists() async throws {
        let obj: [String: Any] = ["a": ["b": ["c": "d", "e": "f"]]]
        let withList: [String: Any] = ["a": ["b": [["c": "d", "e": "f"]]]]

        #expect(try Qs.encode(obj, options: EncodeOptions(encode: false)) == "a[b][c]=d&a[b][e]=f")
        #expect(
            try Qs.encode(obj, options: EncodeOptions(listFormat: .brackets, encode: false))
                == "a[b][c]=d&a[b][e]=f")
        #expect(
            try Qs.encode(obj, options: EncodeOptions(listFormat: .indices, encode: false))
                == "a[b][c]=d&a[b][e]=f")
        #expect(
            try Qs.encode(obj, options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "a[b][c]=d&a[b][e]=f")
        #expect(
            try Qs.encode(obj, options: EncodeOptions(listFormat: .comma, encode: false))
                == "a[b][c]=d&a[b][e]=f")

        #expect(
            try Qs.encode(withList, options: EncodeOptions(encode: false))
                == "a[b][0][c]=d&a[b][0][e]=f")
        #expect(
            try Qs.encode(withList, options: EncodeOptions(listFormat: .brackets, encode: false))
                == "a[b][][c]=d&a[b][][e]=f")
        #expect(
            try Qs.encode(withList, options: EncodeOptions(listFormat: .indices, encode: false))
                == "a[b][0][c]=d&a[b][0][e]=f")
        #expect(
            try Qs.encode(withList, options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "a[b][c]=d&a[b][e]=f")
    }

    @Test("encode - encodes lists with nulls")
    func testEncodesListsWithNulls() async throws {
        let listWithNulls: [Any] = [NSNull(), "2", NSNull(), NSNull(), "1"]

        #expect(
            try Qs.encode(
                ["a": listWithNulls],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=&a[1]=2&a[2]=&a[3]=&a[4]=1"
        )
        #expect(
            try Qs.encode(
                ["a": listWithNulls],
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=&a[]=2&a[]=&a[]=&a[]=1"
        )
        #expect(
            try Qs.encode(
                ["a": listWithNulls],
                options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a=&a=2&a=&a=&a=1"
        )

        let nested1: [String: Any] = ["a": [NSNull(), ["b": [NSNull(), NSNull(), ["c": "1"]]]]]
        #expect(
            try Qs.encode(
                nested1,
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=&a[1][b][0]=&a[1][b][1]=&a[1][b][2][c]=1"
        )
        #expect(
            try Qs.encode(
                nested1,
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=&a[][b][]=&a[][b][]=&a[][b][][c]=1"
        )
        #expect(
            try Qs.encode(
                nested1,
                options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a=&a[b]=&a[b]=&a[b][c]=1"
        )

        let nested2: [String: Any] = [
            "a": [NSNull(), [NSNull(), [NSNull(), NSNull(), ["c": "1"]]]]
        ]
        #expect(
            try Qs.encode(
                nested2,
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=&a[1][0]=&a[1][1][0]=&a[1][1][1]=&a[1][1][2][c]=1"
        )
        #expect(
            try Qs.encode(
                nested2,
                options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=&a[][]=&a[][][]=&a[][][]=&a[][][][c]=1"
        )
        #expect(
            try Qs.encode(
                nested2,
                options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a=&a=&a=&a=&a[c]=1"
        )
    }

    @Test("encode - encodes url")
    func testEncodesUrl() async throws {
        let s = "https://example.com?foo=bar&baz=qux"
        #expect(
            try Qs.encode(
                ["url": s],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "url=https%3A%2F%2Fexample.com%3Ffoo%3Dbar%26baz%3Dqux"
        )

        let url = URL(string: "https://example.com/some/path?foo=bar&baz=qux")!
        #expect(
            try Qs.encode(
                ["url": url],
                options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "url=https%3A%2F%2Fexample.com%2Fsome%2Fpath%3Ffoo%3Dbar%26baz%3Dqux"
        )
    }

    @Test("encode - encodes Spatie map")
    func testEncodesSpatieMap() async throws {
        var filters = OrderedDictionary<String, Any>()
        filters["$or"] = [
            ["date": ["$eq": "2020-01-01"]],
            ["date": ["$eq": "2020-01-02"]],
        ]
        filters["author"] = ["name": ["$eq": "John doe"]]

        let spatie: [String: Any] = ["filters": filters]

        #expect(
            try Qs.encode(spatie, options: EncodeOptions(listFormat: .brackets, encode: false))
                == "filters[$or][][date][$eq]=2020-01-01&filters[$or][][date][$eq]=2020-01-02&filters[author][name][$eq]=John doe"
        )

        #expect(
            try Qs.encode(spatie, options: EncodeOptions(listFormat: .brackets))
                == "filters%5B%24or%5D%5B%5D%5Bdate%5D%5B%24eq%5D=2020-01-01&filters%5B%24or%5D%5B%5D%5Bdate%5D%5B%24eq%5D=2020-01-02&filters%5Bauthor%5D%5Bname%5D%5B%24eq%5D=John%20doe"
        )
    }

    @Test("encode - encodes empty keys: simple cases")
    func testEncodesEmptyKeys_SimpleCases() async throws {
        // primitive under empty key
        #expect(try Qs.encode(["": "v"], options: EncodeOptions(encode: false)) == "=v")

        // list under empty key
        #expect(
            try Qs.encode(
                ["": ["a", "b"]], options: EncodeOptions(listFormat: .indices, encode: false))
                == "[0]=a&[1]=b"
        )
        #expect(
            try Qs.encode(
                ["": ["a", "b"]], options: EncodeOptions(listFormat: .brackets, encode: false))
                == "[]=a&[]=b"
        )
        #expect(
            try Qs.encode(
                ["": ["a", "b"]], options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "=a&=b"
        )
    }

    @Test("encode - encodes empty keys: edge case with map/lists")
    func testEncodesEmptyKeys_EdgeCaseWithMapLists() async throws {
        #expect(
            try Qs.encode(["": ["": [2, 3]]], options: EncodeOptions(encode: false))
                == "[][0]=2&[][1]=3"
        )
        #expect(
            try Qs.encode(["": ["": [2, 3], "a": 2]], options: EncodeOptions(encode: false))
                == "[][0]=2&[][1]=3&[a]=2"
        )
        #expect(
            try Qs.encode(
                ["": ["": [2, 3]]], options: EncodeOptions(listFormat: .indices, encode: false))
                == "[][0]=2&[][1]=3"
        )
        #expect(
            try Qs.encode(
                ["": ["": [2, 3], "a": 2]],
                options: EncodeOptions(listFormat: .indices, encode: false))
                == "[][0]=2&[][1]=3&[a]=2"
        )
    }

    @Test("encode - encodes non-String keys with IterableFilter")
    func testEncodesNonStringKeysWithIterableFilter() async throws {
        // Only the "a" key should be emitted; false and null/NSNull are ignored by the filter
        let options = EncodeOptions(
            allowDots: true, encodeDotInKeys: true, filter: IterableFilter(["a", false, NSNull()])
        )
        #expect(try Qs.encode(["a": "b", "false": [String: Any]()], options: options) == "a=b")
    }

    // MARK: encode non-Strings

    @Test("encode - encodes a null value")
    func testEncodeNullValue() async throws {
        #expect(try Qs.encode(["a": NSNull()]) == "a=")
    }

    @Test("encode - encodes boolean values (non-Strings)")
    func testEncodeBooleanValues_Primitive() async throws {
        #expect(try Qs.encode(["a": true]) == "a=true")
        #expect(try Qs.encode(["a": false]) == "a=false")
    }

    @Test("encode - encodes number values (non-Strings)")
    func testEncodeNumberValues_Primitive() async throws {
        #expect(try Qs.encode(["a": 0]) == "a=0")
        #expect(try Qs.encode(["a": 1]) == "a=1")
        #expect(try Qs.encode(["a": 1.1]) == "a=1.1")
    }

    @Test("encode - encodes a buffer value (Data)")
    func testEncodeBufferValue_Primitive() async throws {
        #expect(try Qs.encode(["a": "test".data(using: .utf8)!]) == "a=test")
    }

    @Test("encode=false serializes Data as decoded text (not Data description)")
    func testEncodeFalse_DataIsStringifiedAsText() async throws {
        let bytes = Data("a b".utf8)
        let plain = try Qs.encode(["a": bytes], options: .init(encode: false))
        #expect(plain == "a=a b")

        let comma = try Qs.encode(["a": [bytes]], options: .init(listFormat: .comma, encode: false))
        #expect(comma == "a=a b")
    }

    @Test("encode=false keeps malformed UTF-8 Data visible")
    func testEncodeFalse_InvalidUTF8DataDoesNotCollapseToEmpty() async throws {
        let invalid = Data([0xC3, 0x28])  // malformed UTF-8 sequence
        let expected = String(decoding: invalid, as: UTF8.self)

        let plain = try Qs.encode(["a": invalid], options: .init(encode: false))
        #expect(plain == "a=\(expected)")

        let comma = try Qs.encode(
            ["a": [invalid]],
            options: .init(listFormat: .comma, encode: false)
        )
        #expect(comma == "a=\(expected)")
    }

    @Test("encode unwraps Optional.some values before stringifying")
    func testEncodeUnwrapsOptionalSomeValues() async throws {
        let optionalInt: Int? = 42
        let optionalText: String? = "hello world"

        let result = try Qs.encode(
            ["a": optionalInt as Any, "b": optionalText as Any],
            options: .init(encode: false)
        )

        let parts = Set(result.split(separator: "&").map(String.init))
        #expect(parts.contains("a=42"))
        #expect(parts.contains("b=hello world"))
        #expect(!parts.contains(where: { $0.contains("Optional(") }))
    }

    @Test("encode unwraps Optional<Data> for plain and comma paths")
    func testEncodeUnwrapsOptionalDataValues() async throws {
        let optionalData: Data? = Data("a b".utf8)

        let plain = try Qs.encode(["a": optionalData as Any], options: .init(encode: false))
        #expect(plain == "a=a b")

        let comma = try Qs.encode(
            ["a": [optionalData as Any]],
            options: .init(listFormat: .comma, encode: false)
        )
        #expect(comma == "a=a b")
    }

    @Test("encode - encodes a date value (non-Strings)")
    func testEncodeDateValue_Primitive() async throws {
        let now = Date()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = "a=\(Utils.encode(f.string(from: now), charset: .utf8, format: .rfc3986))"
        #expect(try Qs.encode(["a": now]) == expected)
    }

    @Test("encode - encodes a list value (non-Strings)")
    func testEncodeListValue_Primitive() async throws {
        #expect(try Qs.encode(["a": [1, 2, 3]]) == "a%5B0%5D=1&a%5B1%5D=2&a%5B2%5D=3")
    }

    @Test("encode - encodes a map value (non-Strings)")
    func testEncodeMapValue_Primitive() async throws {
        #expect(try Qs.encode(["a": ["b": "c"]]) == "a%5Bb%5D=c")
    }

    @Test("encode - encodes a URL/URI value (non-Strings)")
    func testEncodeURI_Primitive() async throws {
        let uri = URL(string: "https://example.com?foo=bar&baz=qux")!
        #expect(try Qs.encode(["a": uri]) == "a=https%3A%2F%2Fexample.com%3Ffoo%3Dbar%26baz%3Dqux")
    }

    @Test("encode - encodes a map with a null map as a child (non-Strings)")
    func testEncodeMapWithNullChild_Primitive() async throws {
        var obj: [String: Any?] = ["a": [String: Any?]()]
        if var child = obj["a"] as? [String: Any?] {
            child["b"] = "c"
            obj["a"] = child
        }
        #expect(try Qs.encode(obj) == "a%5Bb%5D=c")
    }

    private enum DummyEnum: String { case LOREM }

    @Test("encode - encodes a map with an enum as a child")
    func testEncodeMapWithEnumChild() async throws {
        let obj: [String: Any] = [
            "a": DummyEnum.LOREM.rawValue,
            "b": "foo",
            "c": 1,
            "d": 1.234,
            "e": true,
        ]
        #expect(try Qs.encode(obj) == "a=LOREM&b=foo&c=1&d=1.234&e=true")
    }

    @Test("encode - does not encode an Undefined")
    func testDoesNotEncodeUndefined() async throws {
        #expect(try Qs.encode(["a": Undefined()]) == "")
    }

    // MARK: fixed ljharb/qs issues

    @Test("encode - ljharb/qs#493 preserves bracketed key when encode=false")
    func testFixedIssue_qs493() async throws {
        #expect(
            try Qs.encode(
                ["search": ["withbracket[]": "foobar"]],
                options: EncodeOptions(encode: false)
            ) == "search[withbracket[]]=foobar"
        )
    }

    // MARK: encodes Instant

    @Test("encode - Instant with encode=false as ISO_INSTANT (…Z)")
    func testInstant_EncodeFalse_ISOInstant() async throws {
        let inst = Date(timeIntervalSince1970: 0.007)  // 1970-01-01T00:00:00.007Z
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = f.string(from: inst)
        #expect(try Qs.encode(["a": inst], options: EncodeOptions(encode: false)) == "a=\(iso)")
    }

    @Test("encode - Instant with default settings (percent-encoded)")
    func testInstant_DefaultSettings_PercentEncoded() async throws {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let inst = f.date(from: "2020-01-02T03:04:05.006Z")!
        let expected = "a=\(Utils.encode(f.string(from: inst), charset: .utf8, format: .rfc3986))"
        #expect(try Qs.encode(["a": inst]) == expected)
    }

    @Test("encode - COMMA list stringifies Instant elements before join (encode=false)")
    func testInstant_CommaList_Stringifies_EncodeFalse() async throws {
        // Build dates without parsing
        var c1 = DateComponents()
        c1.calendar = Calendar(identifier: .gregorian)
        c1.timeZone = TimeZone(secondsFromGMT: 0)
        c1.year = 2020
        c1.month = 1
        c1.day = 2
        c1.hour = 3
        c1.minute = 4
        c1.second = 5
        let a = c1.date!

        var c2 = DateComponents()
        c2.calendar = Calendar(identifier: .gregorian)
        c2.timeZone = TimeZone(secondsFromGMT: 0)
        c2.year = 2021
        c2.month = 2
        c2.day = 3
        c2.hour = 4
        c2.minute = 5
        c2.second = 6
        let b = c2.date!

        // Expected string (no fractional seconds)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let sa = f.string(from: a)
        let sb = f.string(from: b)

        #expect(
            try Qs.encode(
                ["a": [a, b]],
                options: EncodeOptions(listFormat: .comma, encode: false)
            ) == "a=\(sa),\(sb)"
        )
    }

    @Test("encode - COMMA list encodes comma when encode=true")
    func testInstant_CommaList_EncodesWhenEncodeTrue() async throws {
        // Build dates deterministically (no parsing)
        var c1 = DateComponents()
        c1.calendar = Calendar(identifier: .gregorian)
        c1.timeZone = TimeZone(secondsFromGMT: 0)
        c1.year = 2020
        c1.month = 1
        c1.day = 2
        c1.hour = 3
        c1.minute = 4
        c1.second = 5
        let a = c1.date!

        var c2 = DateComponents()
        c2.calendar = Calendar(identifier: .gregorian)
        c2.timeZone = TimeZone(secondsFromGMT: 0)
        c2.year = 2021
        c2.month = 2
        c2.day = 3
        c2.hour = 4
        c2.minute = 5
        c2.second = 6
        let b = c2.date!

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)

        let joined = "\(f.string(from: a)),\(f.string(from: b))"
        let expected = "a=\(Utils.encode(joined, charset: .utf8, format: .rfc3986))"

        #expect(
            try Qs.encode(["a": [a, b]], options: EncodeOptions(listFormat: .comma)) == expected)
    }

    @Test("encode - single-item COMMA list: no [] by default")
    func testInstant_SingleItemComma_NoBracketsByDefault() async throws {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = 2020
        c.month = 1
        c.day = 2
        c.hour = 3
        c.minute = 4
        c.second = 5
        let only = c.date!

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)

        let s = f.string(from: only)
        #expect(
            try Qs.encode(["a": [only]], options: EncodeOptions(listFormat: .comma, encode: false))
                == "a=\(s)"
        )
    }

    @Test("encode - single-item COMMA list adds [] when commaRoundTrip=true (components)")
    func testInstant_SingleItemComma_AddsBracketsWhenRoundTrip_Components() async throws {
        // Build the date without parsing to avoid formatter strictness
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2020
        comps.month = 1
        comps.day = 2
        comps.hour = 3
        comps.minute = 4
        comps.second = 5
        let only = comps.date!

        // Formatter for expected string (no fractional seconds)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let s = f.string(from: only)

        // Expect: single-item COMMA list uses [] when commaRoundTrip=true
        #expect(
            try Qs.encode(
                ["a": [only]],
                options: EncodeOptions(listFormat: .comma, encode: false, commaRoundTrip: true)
            ) == "a[]=\(s)"
        )
    }

    @Test("encode - indexed list (INDICES) with Instants")
    func testInstant_IndexedList_Default() async throws {
        // Build stable UTC dates
        var c1 = DateComponents()
        c1.calendar = Calendar(identifier: .gregorian)
        c1.timeZone = TimeZone(secondsFromGMT: 0)
        c1.year = 2020
        c1.month = 1
        c1.day = 2
        c1.hour = 3
        c1.minute = 4
        c1.second = 5
        let a = c1.date!

        var c2 = DateComponents()
        c2.calendar = Calendar(identifier: .gregorian)
        c2.timeZone = TimeZone(secondsFromGMT: 0)
        c2.year = 2021
        c2.month = 2
        c2.day = 3
        c2.hour = 4
        c2.minute = 5
        c2.second = 6
        let b = c2.date!

        // Format as ISO8601 without fractional seconds
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)

        let ea = Utils.encode(f.string(from: a), charset: .utf8, format: .rfc3986)
        let eb = Utils.encode(f.string(from: b), charset: .utf8, format: .rfc3986)

        // Default listFormat is .indices and encode=true, so keys/values are percent-encoded
        #expect(try Qs.encode(["a": [a, b]]) == "a%5B0%5D=\(ea)&a%5B1%5D=\(eb)")
    }

    // MARK: - Encoder cycle detection

    #if !os(Linux)
        @Test("Encoder cycle detection – self-referential map throws")
        func testCycleInMapThrows() async throws {
            let a = NSMutableDictionary()
            a["self"] = a  // true cycle

            #expect(throws: EncodeError.cyclicObject) {
                _ = try Qs.encode(["a": a], options: .init())
            }
        }
    #else
        @Test("encode: cycle in map throws (skipped on Linux)")
        func testCycleInMapThrows_skip() throws {
            try withKnownIssue(Comment("Linux: map self-cycle may segfault under corelibs-foundation")) {
                #expect(Bool(false), Comment("Cannot safely construct a dictionary that contains itself on Linux."))
            }
        }
    #endif

    @Test("encode: cycle in list throws EncodeError.cyclicObject")
    func testCycleInListThrows() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: NSArray self-reference may segfault")) {
                #expect(Bool(false), Comment("Cannot safely construct a list that contains itself on Linux."))
            }
        #else
            let a = NSMutableArray()
            a.add(a)
            #expect(throws: EncodeError.cyclicObject) { _ = try Qs.encode(["a": a]) }
        #endif
    }

    @Test("encodeOrNil: cycle dict returns nil")
    func testEncodeOrNilCycleDict() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: NSDictionary self-reference may segfault")) {
                #expect(Bool(false), Comment("Cannot safely evaluate encodeOrNil with cyclic dict on Linux."))
            }
        #else
            let d = NSMutableDictionary()
            d["self"] = d
            #expect(Qs.encodeOrNil(d) == nil)
        #endif
    }

    @Test("encodeOrNil: cycle array returns nil")
    func testEncodeOrNilCycleArray() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: NSArray self-reference may segfault")) {
                #expect(Bool(false), Comment("Cannot safely evaluate encodeOrNil with cyclic array on Linux."))
            }
        #else
            let a = NSMutableArray()
            a.add(a)
            #expect(Qs.encodeOrNil(a) == nil)
        #endif
    }

    @Test("encodeOrEmpty: cycle dict returns empty")
    func testEncodeOrEmptyCycleDict() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: NSDictionary self-reference may segfault")) {
                #expect(Bool(false), Comment("Cannot safely evaluate encodeOrEmpty with cyclic dict on Linux."))
            }
        #else
            let d = NSMutableDictionary()
            d["self"] = d
            let s = Qs.encodeOrEmpty(d)
            #expect(s.isEmpty)
        #endif
    }

    @Test("encodeOrEmpty: cycle array returns empty")
    func testEncodeOrEmptyCycleArray() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: NSArray self-reference may segfault")) {
                #expect(Bool(false), Comment("Cannot safely evaluate encodeOrEmpty with cyclic array on Linux."))
            }
        #else
            let a = NSMutableArray()
            a.add(a)
            let s = Qs.encodeOrEmpty(["a": a])
            #expect(s.isEmpty)
        #endif
    }

    // MARK: Encoder comma list tail paths

    @Test("encode - COMMA list with multiple elements returns a single scalar pair")
    func testCommaList_MultipleElements_SinglePair() async throws {
        #expect(
            try Qs.encode(
                ["a": ["x", "y"]], options: EncodeOptions(listFormat: .comma, encode: false))
                == "a=x,y"
        )
    }

    @Test("encode - COMMA list with single element and round-trip adds []")
    func testCommaList_SingleElement_RoundTripAddsBrackets() async throws {
        // Build a stable UTC date (no parsing pitfalls)
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = 2020
        c.month = 1
        c.day = 2
        c.hour = 3
        c.minute = 4
        c.second = 5
        let only = c.date!

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]  // no fractional seconds
        f.timeZone = TimeZone(secondsFromGMT: 0)

        let s = f.string(from: only)

        #expect(
            try Qs.encode(
                ["a": [only]],
                options: EncodeOptions(listFormat: .comma, encode: false, commaRoundTrip: true)
            ) == "a[]=\(s)"
        )
    }

    @Test("encode - COMMA list with single element and round-trip disabled omits []")
    func testCommaList_SingleElement_RoundTripDisabledOmitsBrackets() async throws {
        #expect(
            try Qs.encode(
                ["a": ["v"]],
                options: EncodeOptions(listFormat: .comma, encode: false, commaRoundTrip: false)
            ) == "a=v"
        )
    }

    // MARK: - Ported from https://github.com/atek-software/qsparser

    @Test("encoding - stringify a querystring object")
    func testEncoding_StringifyQueryStringObject() async throws {
        #expect(try Qs.encode(["a": "b"]) == "a=b")
        #expect(try Qs.encode(["a": 1]) == "a=1")
        #expect(try Qs.encode(["a": 1, "b": 2]) == "a=1&b=2")
        #expect(try Qs.encode(["a": "A_Z"]) == "a=A_Z")
        #expect(try Qs.encode(["a": "€"]) == "a=%E2%82%AC")
        #expect(try Qs.encode(["a": "\u{E000}"]) == "a=%EE%80%80")
        #expect(try Qs.encode(["a": "א"]) == "a=%D7%90")
        #expect(try Qs.encode(["a": "\u{10437}"]) == "a=%F0%90%90%B7")
    }

    @Test("encoding - stringify falsy values")
    func testEncoding_StringifyFalsyValues() async throws {
        #expect(try Qs.encode(nil as Any?) == "")
        #expect(try Qs.encode(nil as Any?, options: EncodeOptions(strictNullHandling: true)) == "")
        #expect(try Qs.encode(false) == "")
        #expect(try Qs.encode(0) == "")
        #expect(try Qs.encode([String: Any]()) == "")
    }

    @Test("encoding - stringify integers with custom encoder")
    func testEncoding_IntegersWithCustomEncoder() async throws {
        let encoder: ValueEncoder = { value, _, _ in
            if let v = value as? Int { return "\(v)n" }
            return value.map { String(describing: $0) } ?? ""
        }
        let options = EncodeOptions(encoder: encoder)
        let optionsValuesOnly = EncodeOptions(
            encoder: encoder, listFormat: .brackets, encodeValuesOnly: true)

        #expect(try Qs.encode(3) == "")
        #expect(try Qs.encode([3]) == "0=3")
        #expect(try Qs.encode([3], options: options) == "0=3n")
        #expect(try Qs.encode(["a": 3]) == "a=3")
        #expect(try Qs.encode(["a": 3], options: options) == "a=3n")
        #expect(
            try Qs.encode(
                ["a": [3]], options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=3")
        #expect(try Qs.encode(["a": [3]], options: optionsValuesOnly) == "a[]=3n")
    }

    @Test("encoding - add query prefix")
    func testEncoding_AddQueryPrefix() async throws {
        let options = EncodeOptions(addQueryPrefix: true)
        #expect(try Qs.encode(["a": "b"], options: options) == "?a=b")
    }

    @Test("encoding - not add query prefix for empty objects")
    func testEncoding_NotAddQueryPrefixForEmpty() async throws {
        let options = EncodeOptions(addQueryPrefix: true)
        #expect(try Qs.encode([String: Any](), options: options) == "")
    }

    @Test("encoding - stringify nested falsy values")
    func testEncoding_StringifyNestedFalsyValues() async throws {
        let nested: [String: Any] = ["a": ["b": ["c": NSNull()]]]
        #expect(try Qs.encode(nested) == "a%5Bb%5D%5Bc%5D=")
        #expect(
            try Qs.encode(nested, options: EncodeOptions(strictNullHandling: true))
                == "a%5Bb%5D%5Bc%5D"
        )
        let qs1 = try Qs.encode(["a": ["b": ["c": false]]])
        #expect(qs1 == "a%5Bb%5D%5Bc%5D=false")
    }

    @Test("encoding - stringify nested objects")
    func testEncoding_StringifyNestedObjects() async throws {
        #expect(try Qs.encode(["a": ["b": "c"]]) == "a%5Bb%5D=c")
        #expect(try Qs.encode(["a": ["b": ["c": ["d": "e"]]]]) == "a%5Bb%5D%5Bc%5D%5Bd%5D=e")
    }

    @Test("encoding - stringify nested objects with dots notation")
    func testEncoding_NestedObjectsWithDots() async throws {
        let options = EncodeOptions(allowDots: true)
        #expect(try Qs.encode(["a": ["b": "c"]], options: options) == "a.b=c")
        #expect(try Qs.encode(["a": ["b": ["c": ["d": "e"]]]], options: options) == "a.b.c.d=e")
    }

    @Test("encoding - stringify array values")
    func testEncoding_ArrayValues() async throws {
        let data: [String: Any] = ["a": ["b", "c", "d"]]
        #expect(
            try Qs.encode(data, options: EncodeOptions(listFormat: .indices))
                == "a%5B0%5D=b&a%5B1%5D=c&a%5B2%5D=d")
        #expect(
            try Qs.encode(data, options: EncodeOptions(listFormat: .brackets))
                == "a%5B%5D=b&a%5B%5D=c&a%5B%5D=d")
        #expect(try Qs.encode(data, options: EncodeOptions(listFormat: .comma)) == "a=b%2Cc%2Cd")
        #expect(try Qs.encode(data) == "a%5B0%5D=b&a%5B1%5D=c&a%5B2%5D=d")
    }

    @Test("encoding - omit nulls when asked")
    func testEncoding_OmitNulls() async throws {
        let options = EncodeOptions(skipNulls: true)
        #expect(try Qs.encode(["a": "b", "c": NSNull()], options: options) == "a=b")
    }

    @Test("encoding - omit nested nulls when asked")
    func testEncoding_OmitNestedNulls() async throws {
        let options = EncodeOptions(skipNulls: true)
        #expect(try Qs.encode(["a": ["b": "c", "d": NSNull()]], options: options) == "a%5Bb%5D=c")
    }

    @Test("encoding - omit array indices when asked")
    func testEncoding_OmitArrayIndices() async throws {
        let options = EncodeOptions(listFormat: .repeatKey)
        #expect(try Qs.encode(["a": ["b", "c", "d"]], options: options) == "a=b&a=c&a=d")
    }

    @Test("encoding - handle non-array items with encodeValuesOnly")
    func testEncoding_HandleNonArrayItems() async throws {
        let options = EncodeOptions(encodeValuesOnly: true)
        let value: [String: Any] = ["a": "c"]
        #expect(try Qs.encode(value, options: options) == "a=c")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a=c")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a=c")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c")
    }

    @Test("encoding - handle array with single item")
    func testEncoding_HandleArraySingleItem() async throws {
        let options = EncodeOptions(encodeValuesOnly: true)
        let value: [String: Any] = ["a": ["c"]]
        #expect(try Qs.encode(value, options: options) == "a[0]=c")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=c")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=c")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c")
        #expect(
            try Qs.encode(
                value,
                options: EncodeOptions(
                    listFormat: .comma, encodeValuesOnly: true, commaRoundTrip: true))
                == "a[]=c")
    }

    @Test("encoding - handle array with multiple items")
    func testEncoding_HandleArrayMultipleItems() async throws {
        let options = EncodeOptions(encodeValuesOnly: true)
        let value: [String: Any] = ["a": ["c", "d"]]
        #expect(try Qs.encode(value, options: options) == "a[0]=c&a[1]=d")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=c&a[1]=d")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=c&a[]=d")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c,d")
    }

    @Test("encoding - handle array with multiple items containing commas")
    func testEncoding_HandleArrayMultipleItemsWithCommas() async throws {
        let value: [String: Any] = ["a": ["c,d", "e"]]
        #expect(try Qs.encode(value, options: EncodeOptions(listFormat: .comma)) == "a=c%2Cd%2Ce")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=c%2Cd,e")
    }

    @Test("encoding - stringify nested array values")
    func testEncoding_StringifyNestedArrayValues() async throws {
        let options = EncodeOptions(encodeValuesOnly: true)
        let value: [String: Any] = ["a": ["b": ["c", "d"]]]
        #expect(try Qs.encode(value, options: options) == "a[b][0]=c&a[b][1]=d")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[b][0]=c&a[b][1]=d")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[b][]=c&a[b][]=d")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a[b]=c,d")
    }

    @Test("encoding - stringify comma and empty array values")
    func testEncoding_StringifyCommaAndEmptyArrayValues() async throws {
        let value: [String: Any] = ["a": [",", "", "c,d%"]]

        // encode=false
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .indices, encode: false))
                == "a[0]=,&a[1]=&a[2]=c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .brackets, encode: false))
                == "a[]=,&a[]=&a[]=c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encode: false))
                == "a=,,,c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "a=,&a=&a=c,d%")

        // encodeValuesOnly=true
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0]=%2C&a[1]=&a[2]=c%2Cd%25")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[]=%2C&a[]=&a[]=c%2Cd%25")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
                == "a=%2C,,c%2Cd%25")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: true))
                == "a=%2C&a=&a=c%2Cd%25")

        // encode keys and values
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: false))
                == "a%5B0%5D=%2C&a%5B1%5D=&a%5B2%5D=c%2Cd%25")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: false))
                == "a%5B%5D=%2C&a%5B%5D=&a%5B%5D=c%2Cd%25")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: false))
                == "a=%2C%2C%2Cc%2Cd%25")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .repeatKey, encodeValuesOnly: false))
                == "a=%2C&a=&a=c%2Cd%25")
    }

    @Test("encoding - stringify comma and empty non-array values")
    func testEncoding_StringifyCommaAndEmptyNonArrayValues() async throws {
        let value: [String: Any] = ["a": ",", "b": "", "c": "c,d%"]
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .indices, encode: false))
                == "a=,&b=&c=c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .brackets, encode: false))
                == "a=,&b=&c=c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .comma, encode: false))
                == "a=,&b=&c=c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .repeatKey, encode: false))
                == "a=,&b=&c=c,d%")
        #expect(
            try Qs.encode(value, options: EncodeOptions(encodeValuesOnly: true))
                == "a=%2C&b=&c=c%2Cd%25")
        #expect(
            try Qs.encode(value, options: EncodeOptions(encodeValuesOnly: false))
                == "a=%2C&b=&c=c%2Cd%25")
    }

    @Test("encoding - stringify nested array values with dots notation")
    func testEncoding_NestedArrayValuesWithDots() async throws {
        let value: [String: Any] = ["a": ["b": ["c", "d"]]]
        let options = EncodeOptions(allowDots: true, encodeValuesOnly: true)
        #expect(try Qs.encode(value, options: options) == "a.b[0]=c&a.b[1]=d")
        #expect(
            try Qs.encode(
                value,
                options: EncodeOptions(
                    listFormat: .indices, allowDots: true, encodeValuesOnly: true))
                == "a.b[0]=c&a.b[1]=d")
        #expect(
            try Qs.encode(
                value,
                options: EncodeOptions(
                    listFormat: .brackets, allowDots: true, encodeValuesOnly: true))
                == "a.b[]=c&a.b[]=d")
        #expect(
            try Qs.encode(
                value,
                options: EncodeOptions(listFormat: .comma, allowDots: true, encodeValuesOnly: true))
                == "a.b=c,d")
    }

    @Test("encoding - stringify objects inside arrays")
    func testEncoding_ObjectsInsideArrays() async throws {
        let value: [String: Any] = ["a": [["b": "c"]]]
        let value2: [String: Any] = ["a": [["b": ["c": [1]]]]]
        #expect(try Qs.encode(value) == "a%5B0%5D%5Bb%5D=c")
        #expect(try Qs.encode(value2) == "a%5B0%5D%5Bb%5D%5Bc%5D%5B0%5D=1")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .indices))
                == "a%5B0%5D%5Bb%5D=c")
        #expect(
            try Qs.encode(value2, options: EncodeOptions(listFormat: .indices))
                == "a%5B0%5D%5Bb%5D%5Bc%5D%5B0%5D=1")
        #expect(
            try Qs.encode(value, options: EncodeOptions(listFormat: .brackets))
                == "a%5B%5D%5Bb%5D=c")
        #expect(
            try Qs.encode(value2, options: EncodeOptions(listFormat: .brackets))
                == "a%5B%5D%5Bb%5D%5Bc%5D%5B%5D=1")
    }

    @Test("encoding - stringify arrays with mixed objects and primitives")
    func testEncoding_ArraysWithMixedObjectsAndPrimitives() async throws {
        let value: [String: Any] = ["a": [["b": 1], 2, 3]]
        let options = EncodeOptions(encodeValuesOnly: true)
        #expect(try Qs.encode(value, options: options) == "a[0][b]=1&a[1]=2&a[2]=3")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .indices, encodeValuesOnly: true))
                == "a[0][b]=1&a[1]=2&a[2]=3")
        #expect(
            try Qs.encode(
                value, options: EncodeOptions(listFormat: .brackets, encodeValuesOnly: true))
                == "a[][b]=1&a[]=2&a[]=3")
        let commaResult = try Qs.encode(
            value, options: EncodeOptions(listFormat: .comma, encodeValuesOnly: true))
        #expect(commaResult.contains("a="))
    }

    // MARK: - NSDictionary

    @Test("encode: NSDictionary behaves like [String:Any] (order-insensitive across keys)")
    func nsdictionary_encodes_like_swift_dict_order_insensitive() throws {
        let inner: NSDictionary = ["": [2, 3], "a": 2]
        let out = try Qs.encode(["": inner], options: EncodeOptions(encode: false))

        let parts = out.split(separator: "&").map(String.init)
        // All required pairs must be present
        #expect(Set(parts) == Set(["[][0]=2", "[][1]=3", "[a]=2"]))

        // Still enforce array element ordering (0 before 1)
        let i0 = parts.firstIndex(of: "[][0]=2")
        let i1 = parts.firstIndex(of: "[][1]=3")
        #expect(i0 != nil && i1 != nil && i0! < i1!)
    }

    @Test("Encoder.encode: NSDictionary cycle throws EncodeError.cyclicObject")
    func nsdictionary_cycle_throws() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: NSDictionary self-cycle may segfault under corelibs-foundation")) {
                #expect(
                    Bool(false),
                    Comment("Cannot safely construct NSDictionary self-cycle on Linux; tracked as known issue."))
            }
        #else
            let m = NSMutableDictionary()
            m["self"] = m
            #expect(throws: EncodeError.cyclicObject) { _ = try Qs.encode(["outer": m]) }
        #endif
    }

    // MARK: - Edge cases

    @Test(
        "encode: OrderedDictionary<String,Any> partitions containers and sorts both halves at nested depth"
    )
    func sort_orderedDict_string_keys_nestedPartition() throws {
        // Parent dict (depth 0) has a nested dict so children encode at depth 1.
        let child: OrderedDictionary<String, Any> = [
            "zContainer": ["k": "v"],  // container → should be sorted after primitives
            "aPrim": "1",
            "bPrim": "2",
        ]
        let root: OrderedDictionary<String, Any> = [
            "child": child
        ]

        // Force `encoder != nil` so the nested block sorts both primitive and container halves.
        let opts = EncodeOptions(
            encoder: { v, _, _ in String(describing: v ?? "") }
        )

        let out = try Qs.encode(root, options: opts)
        // child’s primitive keys aPrim,bPrim should come before zContainer; each group A..Z
        #expect(out == "child[aPrim]=1&child[bPrim]=2&child[zContainer][k]=v")
    }

    @Test(
        "encode: OrderedDictionary<String,Any> nested depth partitions primitives before containers with encoder=nil (stable)"
    )
    func sort_orderedDict_string_keys_nestedPartition_encoderNilStable() throws {
        let child: OrderedDictionary<String, Any> = [
            "zContainer": ["k": "v"],
            "bPrim": "2",
            "aPrim": "1",
            "yContainer": ["m": "n"],
        ]
        let root: OrderedDictionary<String, Any> = [
            "child": child
        ]

        let out = try Qs.encode(root, options: .init(encode: false))
        #expect(out == "child[bPrim]=2&child[aPrim]=1&child[zContainer][k]=v&child[yContainer][m]=n")
    }

    @Test("encode: .comma + empty list returns no pairs (Undefined sentinel path)")
    func comma_empty_returns_no_pairs() throws {
        let opts = EncodeOptions(listFormat: .comma)
        // Top-level has no prefix, so this yields no "k=" pair at all.
        let out = try Qs.encode([Any](), options: opts)
        #expect(out == "")
    }

    @Test("encode: .comma + single element + commaRoundTrip adds [] to key")
    func comma_single_element_roundtrip() throws {
        let payload: [String: Any] = ["a": ["x"]]
        let opts = EncodeOptions(listFormat: .comma, commaRoundTrip: true)
        let out = try Qs.encode(payload, options: opts)
        #expect(out == "a%5B%5D=x")
    }

    @Test("encode: .comma + commaCompactNulls drops NSNull entries before joining")
    func comma_compactNulls_drops_NSNull_entries() throws {
        let payload: [String: Any] = [
            "a": ["b": ["one", NSNull(), "two", NSNull(), "three"]]
        ]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(listFormat: .comma, encode: false)
        )
        #expect(baseline == "a[b]=one,,two,,three")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaCompactNulls: true
            )
        )
        #expect(compact == "a[b]=one,two,three")
    }

    @Test("encode: .comma + commaCompactNulls drops optional nil entries before joining")
    func comma_compactNulls_drops_optional_nil_entries() throws {
        let payload: [String: Any] = ["a": ["one", nil, "two", nil, "three"] as [String?]]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(listFormat: .comma, encode: false)
        )
        #expect(baseline == "a=one,,two,,three")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaCompactNulls: true
            )
        )
        #expect(compact == "a=one,two,three")
    }

    @Test("encode: .comma + commaCompactNulls omits the key when all entries are null")
    func comma_compactNulls_omits_all_NSNulls() throws {
        let payload: [String: Any] = ["a": [NSNull(), NSNull()]]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(listFormat: .comma, encode: false)
        )
        #expect(baseline == "a=,")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaCompactNulls: true
            )
        )
        #expect(compact.isEmpty)
    }

    @Test("encode: .comma + commaCompactNulls omits the key when all entries are null")
    func comma_compactNulls_omits_all_nil() throws {
        let payload: [String: Any] = ["a": [nil, nil]]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(listFormat: .comma, encode: false)
        )
        #expect(baseline == "a=,")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaCompactNulls: true
            )
        )
        #expect(compact.isEmpty)
    }

    @Test("encode: .comma + commaCompactNulls omits the key when all entries are null")
    func comma_compactNulls_omits_all_NSNull_and_nil() throws {
        let payload: [String: Any] = ["a": [NSNull(), nil]]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(listFormat: .comma, encode: false)
        )
        #expect(baseline == "a=,")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaCompactNulls: true
            )
        )
        #expect(compact.isEmpty)
    }

    @Test("encode: .comma + commaCompactNulls preserves round-trip marker after filtering")
    func comma_compactNulls_preserves_round_trip_marker_NSNull() throws {
        let payload: [String: Any] = ["a": [NSNull(), "foo"]]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaRoundTrip: true
            )
        )
        #expect(baseline == "a=,foo")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaRoundTrip: true,
                commaCompactNulls: true
            )
        )
        #expect(compact == "a[]=foo")
    }

    @Test("encode: .comma + commaCompactNulls preserves round-trip marker after filtering")
    func comma_compactNulls_preserves_round_trip_marker_nil() throws {
        let payload: [String: Any] = ["a": [nil, "foo"]]

        let baseline = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaRoundTrip: true
            )
        )
        #expect(baseline == "a=,foo")

        let compact = try Qs.encode(
            payload,
            options: EncodeOptions(
                listFormat: .comma,
                encode: false,
                commaRoundTrip: true,
                commaCompactNulls: true
            )
        )
        #expect(compact == "a[]=foo")
    }

    @Test("encode: .comma + encode=true + valuesOnly + commaCompactNulls")
    func comma_compactNulls_valuesOnly_encodes_once() throws {
        let payload: [String: Any] = ["a": ["c,d", NSNull(), "e%"]]
        let opts = EncodeOptions(listFormat: .comma, encode: true, encodeValuesOnly: true, commaCompactNulls: true)
        // Expect comma preserved as %2C and '%' encoded once
        #expect(try Qs.encode(payload, options: opts) == "a=c%2Cd,e%25")
    }

    @Test("encode: allowEmptyLists renders foo[] for empty arrays")
    func empty_list_emits_brackets() throws {
        let opts = EncodeOptions(allowEmptyLists: true)
        let out = try Qs.encode(["foo": []], options: opts)
        #expect(out == "foo[]")
    }

    @Test("encode: NSNull non-strict yields key=")
    func nsnull_non_strict() throws {
        let out = try Qs.encode(["a": NSNull()])
        #expect(out == "a=")
    }

    @Test("encode: NSNull strict yields bare key")
    func nsnull_strict() throws {
        let out = try Qs.encode(["a": NSNull()], options: .init(strictNullHandling: true))
        #expect(out == "a")
    }

    @Test("encode: skipNulls drops NSNull leaf")
    func skip_nulls_drops() throws {
        let opts = EncodeOptions(skipNulls: true)
        let out = try Qs.encode(["a": NSNull(), "b": "1"], options: opts)
        #expect(out == "b=1")
    }

    @Test("encode: IterableFilter supplies custom key iteration order")
    func iterable_filter_orders_keys() throws {
        let payload: [String: Any] = ["b": "2", "a": "1", "c": "3"]
        let filter = IterableFilter(["c", "a", "b"])  // desired order
        let out = try Qs.encode(payload, options: .init(filter: filter))
        #expect(out == "c=3&a=1&b=2")
    }

    @Test("encode: FunctionFilter adopts container only when original was a container")
    func function_filter_adoption_rules() throws {
        // For a primitive leaf, filter returns a container → should NOT adopt (keeps primitive).
        let f1 = FunctionFilter { key, value in
            // Leave the root alone; only return a container at leaves.
            if key.isEmpty { return value }
            return ["x": "y"] as [String: Any]
        }
        let out1 = try Qs.encode(["a": "1"], options: .init(filter: f1))
        #expect(out1 == "a=1")

        // For a container leaf, filter returns scalar → should adopt.
        let f2 = FunctionFilter { key, value in
            if key.isEmpty { return value }  // don't touch the root
            if value is [String: Any] { return "ZZ" }  // replace container leaf with scalar
            return value
        }
        let out2 = try Qs.encode(["a": ["b": "1"]], options: .init(filter: f2))
        #expect(out2 == "a=ZZ")
    }

    @Test("allowDots + encodeDotInKeys (default encode) matches qs.js")
    func dots_and_percent2e_default_encoder() throws {
        let payload = ["a": ["b.c": "v"]]
        let opts = EncodeOptions(allowDots: true, encodeDotInKeys: true)  // encode = true (default)
        let out = try Qs.encode(payload, options: opts)
        // qs.js: "a.b%252Ec=v"
        #expect(out == "a.b%252Ec=v")
    }

    @Test("allowDots + encodeDotInKeys with encode=false keeps single %2E")
    func dots_and_percent2e_no_encode() throws {
        let payload = ["a": ["b.c": "v"]]
        let opts = EncodeOptions(allowDots: true, encode: false, encodeDotInKeys: true)
        let out = try Qs.encode(payload, options: opts)
        // No second pass encoder -> single-encoded
        #expect(out == "a.b%2Ec=v")
    }

    @Test("encode: cycle throws EncodeError.cyclicObject")
    func cycle_throws() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: self-referential Foundation containers can crash before encoder runs")) {
                #expect(
                    Bool(false), Comment("Cannot safely build a generic self-cycle on Linux; tracked as known issue.")
                )
            }
        #else
            let a = NSMutableDictionary()
            a["a"] = a
            #expect(throws: EncodeError.cyclicObject) { _ = try Qs.encode(a) }
        #endif
    }

    @Test("encode: array cycle throws EncodeError.cyclicObject")
    func array_cycle_throws() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: corelibs-foundation segfault when constructing NSArray self-cycle")) {
                #expect(
                    Bool(false), Comment("Cannot safely construct NSArray self-cycle on Linux; tracked as known issue.")
                )
            }
        #else
            let a = NSMutableArray()
            a.add(a)
            #expect(throws: EncodeError.cyclicObject) {
                _ = try Qs.encode(["root": a], options: .init())
            }
        #endif
    }

    @Test("encode: NSDictionary/Dictionary cycle throws EncodeError.cyclicObject")
    func cycle_dict_ref_throws() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: corelibs-foundation segfault when constructing NSDictionary self-cycle"))
            {
                #expect(
                    Bool(false),
                    Comment("Cannot safely construct NSDictionary self-cycle on Linux; tracked as known issue."))
            }
        #else
            let d = NSMutableDictionary()
            d["self"] = d
            #expect(throws: EncodeError.cyclicObject) { _ = try Qs.encode(["root": d]) }
        #endif
    }

    @Test("encode: NSMutableArray self-cycle throws EncodeError.cyclicObject")
    func cycle_array_ref_throws() throws {
        #if os(Linux)
            try withKnownIssue(
                Comment("Linux: corelibs-foundation segfault when constructing NSMutableArray self-cycle")
            ) {
                #expect(
                    Bool(false),
                    Comment("Cannot safely construct NSMutableArray self-cycle on Linux; tracked as known issue."))
            }
        #else
            let a = NSMutableArray()
            a.add(a)
            #expect(throws: EncodeError.cyclicObject) {
                _ = try Qs.encode(["root": a])
            }
        #endif
    }

    @Test("encode: cross-referenced containers throw EncodeError.cyclicObject")
    func cycle_cross_ref_throws() throws {
        #if os(Linux)
            try withKnownIssue(Comment("Linux: corelibs-foundation may segfault on cross-referential containers")) {
                #expect(
                    Bool(false),
                    Comment("Cannot safely construct cross-referential NSDictionary/NSArray graph on Linux."))
            }
        #else
            let a = NSMutableArray()
            let b = NSMutableArray()
            a.add(b)
            b.add(a)
            #expect(throws: EncodeError.cyclicObject) { _ = try Qs.encode(["root": a]) }
        #endif
    }

    @Test("encode: default ISO8601 date serializer uses fractional seconds when present")
    func date_iso8601_fractional() throws {
        let withMillis = Date(timeIntervalSince1970: 1.234)
        let noMillis = Date(timeIntervalSince1970: 2.0)

        let out = try Qs.encode(["a": withMillis, "b": noMillis])
        // Shapes (don’t pin exact time zone if you don’t want brittleness)
        #expect(out.contains("a=") && out.contains("b="))
        #expect(out.contains(".234"))  // fractional seconds present
        #expect(!out.contains("b=."))
    }

    // MARK: - NSDictionary-specific tests

    // 1) NSDictionary + explicit Sorter → hits the `if let sort = sort` branch
    @Test("encode: NSDictionary uses provided Sorter for key order")
    func nsdictionary_sorted_by_sorter() throws {
        // Unordered NSDictionary on purpose
        let nd: NSDictionary = ["b": "2", "a": "1", "c": "3"]

        // Sort by String(describing:) ascending
        let sorter: Sorter = { a, b in
            let sa = a.map { String(describing: $0) } ?? ""
            let sb = b.map { String(describing: $0) } ?? ""
            return sa.compare(sb).rawValue
        }

        // Turn off percent-encoding so expectations are easier to read
        let out = try Qs.encode(["wrap": nd], options: .init(encode: false, sort: sorter))
        #expect(out == "wrap[a]=1&wrap[b]=2&wrap[c]=3")
    }

    // 2) NSDictionary at depth > 0 + encoder != nil → partition primitives first, containers last
    @Test("encode: NSDictionary depth>0 partitions prims before containers when encoder is non-nil")
    func nsdictionary_partition_with_encoder() throws {
        // "a" → primitive; "B" → container
        let inner: NSDictionary = ["B": ["x": 1], "a": 1]

        // Default options.percent-encode => encoder is non-nil in the recursive call
        // Expect prim "a" before container "B"
        let out = try Qs.encode(["wrap": inner])  // encode=true by default

        // Percent-encoded brackets:
        // wrap[a]=1           → "wrap%5Ba%5D=1"
        // wrap[B][x]=1        → "wrap%5BB%5D%5Bx%5D=1"
        #expect(out == "wrap%5Ba%5D=1&wrap%5BB%5D%5Bx%5D=1")
    }

    // 3) NSDictionary at depth > 0 + encoder == nil → fallback lexicographic sort of keys
    @Test("encode: NSDictionary depth>0 (no encoder) produces expected pairs (order agnostic)")
    func nsdictionary_depth_no_encoder_pairs() throws {
        // Empty key "" and normal key "a"
        let inner: NSDictionary = ["": [2, 3], "a": 2]

        // encode=false ⇒ recursive encoder has encoder == nil (hits the NSDictionary depth>0 path)
        let out = try Qs.encode(["": inner], options: .init(encode: false))

        // Compare as sets of pairs to avoid dependence on NSDictionary enumeration order
        let got = Set(out.split(separator: "&").map(String.init))
        let expected: Set<String> = ["[][0]=2", "[][1]=3", "[a]=2"]

        #expect(got == expected)
    }

    @Test("Encoder.encode: NSDictionary + custom Sorter (direct)")
    func enc_nsdict_custom_sorter_direct() throws {
        let nd: NSDictionary = ["b": 2, "a": 1, "c": 3]

        // Sort descending by string form so the order is obvious: c > b > a
        let sorter: Sorter = { a, b in
            let sa = a.map { String(describing: $0) } ?? ""
            let sb = b.map { String(describing: $0) } ?? ""
            return sb.compare(sa).rawValue
        }

        let side = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()

        let any = try Encoder.encode(
            data: nd,
            undefined: false,
            sideChannel: side,
            prefix: "outer",
            generateArrayPrefix: ListFormat.indices.generator,
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,  // keep brackets unencoded
            serializeDate: nil,
            sort: sorter,  // <-- hits the "if let sort" path
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 1  // ensure depth > 0
        )

        let s =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)
        #expect(s == "outer[c]=3&outer[b]=2&outer[a]=1")
    }

    @Test(
        "Encoder.encode: NSDictionary depth>0 (encoder != nil) partitions primitives before containers"
    )
    func enc_nsdict_depth_encoder_partitions() throws {
        // primitives: "a"=1, "d"=0; containers: "b"={x:1}, "c"={y:2}
        let nd: NSDictionary = [
            "b": ["x": 1],
            "a": 1,
            "c": ["y": 2],
            "d": 0,
        ]

        // Non-nil encoder to trigger the partition branch; identity is fine.
        let identity: ValueEncoder = { v, _, _ in String(describing: v ?? "") }

        let side = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()

        let any = try Encoder.encode(
            data: nd,
            undefined: false,
            sideChannel: side,
            prefix: "outer",
            generateArrayPrefix: ListFormat.indices.generator,
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: identity,  // <-- encoder != nil triggers partition+sort
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 1
        )

        let s =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)
        // primitives ("a","d") A..Z first, then containers ("b","c") A..Z
        #expect(s == "outer[a]=1&outer[d]=0&outer[b][x]=1&outer[c][y]=2")
    }

    @Test("Encoder.encode: NSDictionary depth>0 (encoder == nil) uses lexicographic fallback")
    func enc_nsdict_depth_no_encoder_lex_sort() throws {
        // Empty key "" and normal key "a"
        let nd: NSDictionary = ["": [2, 3], "a": 2]

        let any = try Encoder.encode(
            data: nd,
            undefined: false,
            sideChannel: NSMapTable.weakToWeakObjects(),
            prefix: "",
            generateArrayPrefix: ListFormat.indices.generator,
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,  // <- encoder == nil
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 1
        )

        let s =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)

        // Order-insensitive assertion
        let expected = "[][0]=2&[][1]=3&[a]=2"
        #expect(multisetParts(s) == multisetParts(expected))
    }

    @Test("NSDictionary lex path is used at depth>0 with encoder=nil")
    func nsdict_lex_path_hits() throws {
        let nd: NSDictionary = ["": [2, 3], "a": 2]
        let side = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()

        let any = try Encoder.encode(
            data: nd,
            undefined: false,
            sideChannel: side,
            prefix: "",
            generateArrayPrefix: ListFormat.indices.generator,
            listFormat: .indices,
            encoder: nil,
            depth: 1
        )

        let s =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)

        // Order-insensitive assertion
        let expected = "[][0]=2&[][1]=3&[a]=2"
        #expect(multisetParts(s) == multisetParts(expected))
    }

    @Test(
        "Encoder.encode: NSDictionary depth>0 (encoder != nil) partitions primitives before containers (NSDictionary path)"
    )
    func enc_nsdict_depth_encoder_partitioning() throws {
        // Mix of primitive and container values
        let nd: NSDictionary = [
            "b": ["x": 1],  // container
            "a": 1,  // primitive
            "c": ["y": 2],  // container
            "d": 0,  // primitive
        ]

        // Non-nil encoder to trigger the partition branch; identity is fine
        let idEnc: ValueEncoder = { value, _, _ in
            if let s = value as? String { return s }
            return String(describing: value ?? "")
        }

        let any = try Encoder.encode(
            data: nd,
            undefined: false,
            sideChannel: NSMapTable<AnyObject, AnyObject>.weakToWeakObjects(),
            prefix: "outer",
            generateArrayPrefix: ListFormat.indices.generator,
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: idEnc,  // <- encoder != nil
            serializeDate: nil,
            sort: nil,  // <- no external sort
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 1  // <- depth > 0
        )

        let s =
            (any as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
            ?? String(describing: any)

        // primitives ("a","d") A..Z first, then containers ("b","c") A..Z
        #expect(s == "outer[a]=1&outer[d]=0&outer[b][x]=1&outer[c][y]=2")
    }

    @Test(
        "Qs.encode: NSDictionary nested – partitions primitives before containers (encoder != nil)"
    )
    func qs_nsdict_partitioning_percentEncoded() throws {
        // Same payload nested under a single top-level key (stable)
        let nd: NSDictionary = ["b": ["x": 1], "a": 1, "c": ["y": 2], "d": 0]

        // Qs.encode will pass a non-nil percent-encoder to the recursive call
        let out = try Qs.encode(["outer": nd])

        // outer[a]=1&outer[d]=0&outer[b][x]=1&outer[c][y]=2 (percent-encoded brackets)
        #expect(out == "outer%5Ba%5D=1&outer%5Bd%5D=0&outer%5Bb%5D%5Bx%5D=1&outer%5Bc%5D%5By%5D=2")
    }

    // MARK: - Empty keys across list formats

    @Test("encode: map with empty-string key across list formats (parametrized)")
    func encodes_empty_key_across_list_formats() throws {
        for (i, element) in emptyTestCases().enumerated() {
            let label = (element["input"] as? String) ?? "case \(i)"

            let withEmptyKeys = element["withEmptyKeys"] as! [String: Any]
            let stringifyOutput = element["stringifyOutput"] as! [String: String]

            // indices
            let outIndices = try Qs.encode(
                withEmptyKeys,
                options: EncodeOptions(listFormat: .indices, encode: false)
            )
            #expect(outIndices == (stringifyOutput["indices"] ?? ""), "\(label) (indices)")

            // brackets
            let outBrackets = try Qs.encode(
                withEmptyKeys,
                options: EncodeOptions(listFormat: .brackets, encode: false)
            )
            #expect(outBrackets == (stringifyOutput["brackets"] ?? ""), "\(label) (brackets)")

            // repeat
            let outRepeat = try Qs.encode(
                withEmptyKeys,
                options: EncodeOptions(listFormat: .repeatKey, encode: false)
            )
            #expect(outRepeat == (stringifyOutput["repeat"] ?? ""), "\(label) (repeat)")
        }
    }

    #if canImport(Darwin)
        @Test("Encoder.encode drops NSNull entries inside containers when skipNulls is true")
        func encoder_skipNulls_dropsNSNull() throws {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let result = try Encoder.encode(
                data: ["a": NSNull()],
                undefined: false,
                sideChannel: sideChannel,
                prefix: nil,
                listFormat: .indices,
                commaRoundTrip: false,
                allowEmptyLists: false,
                strictNullHandling: false,
                skipNulls: true,
                encodeDotInKeys: false,
                encoder: nil,
                serializeDate: nil,
                sort: nil,
                filter: nil,
                allowDots: false,
                format: .rfc3986,
                formatter: nil,
                encodeValuesOnly: false,
                charset: .utf8,
                addQueryPrefix: false,
                depth: 0
            )

            if let array = result as? [Any] {
                #expect(array.isEmpty)
            } else {
                Issue.record("Expected empty array from skipNulls branch, got: \(String(describing: result))")
            }
        }
    #endif

    #if canImport(Darwin)
        @Test("Encoder.encode short-circuits when undefined flag is true")
        func encoder_undefined_flag_returnsEmpty() throws {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let result = try Encoder.encode(
                data: ["k": "v"],
                undefined: true,
                sideChannel: sideChannel,
                prefix: "k",
                listFormat: .indices,
                commaRoundTrip: false,
                allowEmptyLists: false,
                strictNullHandling: false,
                skipNulls: false,
                encodeDotInKeys: false,
                encoder: nil,
                serializeDate: nil,
                sort: nil,
                filter: nil,
                allowDots: false,
                format: .rfc3986,
                formatter: nil,
                encodeValuesOnly: false,
                charset: .utf8,
                addQueryPrefix: false,
                depth: 0
            )

            if let array = result as? [Any] {
                #expect(array.isEmpty)
            } else {
                Issue.record("Expected empty array from undefined branch, got: \(String(describing: result))")
            }
        }
    #endif

    @Test("Encoder.encode strictNullHandling key-only path for nil values")
    func encoder_strictNullHandling_nilKeyOnly() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()

        let noEncoder = try Encoder.encode(
            data: nil,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "flag",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: true,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 0
        )
        #expect(noEncoder as? String == "flag")

        let identity: ValueEncoder = { value, _, _ in String(describing: value ?? "") }
        let withEncoder = try Encoder.encode(
            data: nil,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "flag",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: true,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: identity,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 0
        )
        #expect(withEncoder as? String == "flag")
    }

    @Test("Encoder.encode deep fallback handles list traversal")
    func encoder_iterativeFallback_listTraversal() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let result = try Encoder.encode(
            data: [1, 2],
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        let s = (result as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
        #expect(s == "a[0]=1&a[1]=2")
    }

    @Test("Encoder.encode deep fallback does not flag large acyclic input as cyclic")
    func encoder_iterativeFallback_largeAcyclic_noFalseCycle() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let large: [Any] = Array(repeating: [Any](), count: 250_001)

        let result = try Encoder.encode(
            data: large,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )

        if let array = result as? [Any] {
            #expect(array.isEmpty)
        } else {
            Issue.record("Expected empty encoded parts for acyclic empty children")
        }
    }

    #if canImport(Darwin)
        @Test("Encoder.encode deep fallback detects NSDictionary cycles")
        func encoder_iterativeFallback_detectsNSDictionaryCycle() throws {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let cyclic = NSMutableDictionary()
            cyclic["self"] = cyclic

            #expect(throws: EncodeError.cyclicObject) {
                _ = try Encoder.encode(
                    data: cyclic,
                    undefined: false,
                    sideChannel: sideChannel,
                    prefix: "a",
                    listFormat: .indices,
                    commaRoundTrip: false,
                    allowEmptyLists: false,
                    strictNullHandling: false,
                    skipNulls: false,
                    encodeDotInKeys: false,
                    encoder: nil,
                    serializeDate: nil,
                    sort: nil,
                    filter: nil,
                    allowDots: false,
                    format: .rfc3986,
                    formatter: nil,
                    encodeValuesOnly: false,
                    charset: .utf8,
                    addQueryPrefix: false,
                    depth: 512
                )
            }
        }
    #endif

    @Test("Encoder.encode deep fallback handles NSDictionary traversal")
    func encoder_iterativeFallback_nsdictionaryTraversal() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let result = try Encoder.encode(
            data: NSDictionary(dictionary: ["b": 2]),
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        let s = (result as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
        #expect(s == "a[b]=2")
    }

    @Test("Encoder.encode deep fallback handles scalar edge cases")
    func encoder_iterativeFallback_scalarEdges() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()

        let nilResult = try Encoder.encode(
            data: nil,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        #expect(nilResult as? String == "a=")

        let nullResult = try Encoder.encode(
            data: NSNull(),
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        #expect(nullResult as? String == "a=")
    }

    @Test("Encoder.encode deep fallback NSNull path uses custom encoder")
    func encoder_iterativeFallback_nsnullCustomEncoder() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let custom: ValueEncoder = { value, _, _ in
            if let key = value as? String { return "k_\(key)" }
            guard let value else { return "null_token" }
            return "v_\(String(describing: value))"
        }

        let result = try Encoder.encode(
            data: NSNull(),
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: custom,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        #expect(result as? String == "k_a=k_")
    }

    @Test("Encoder.encode deep fallback tracks NSArray roots for cycle identity")
    func encoder_iterativeFallback_nsarrayRootUsesContainerIdentity() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let result = try Encoder.encode(
            data: NSArray(array: [1, 2]),
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        let s = (result as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
        #expect(s == "a[0]=1&a[1]=2")
    }

    @Test("Encoder.encode deep fallback orders OrderedDictionary primitives before containers")
    func encoder_iterativeFallback_orderedDictionaryPartition_withEncoder() throws {
        var data = OrderedDictionary<String, Any>()
        data["b"] = ["x": 1]
        data["a"] = 1
        data["c"] = 2

        let identity: ValueEncoder = { value, _, _ in String(describing: value ?? "") }
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let result = try Encoder.encode(
            data: data,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: identity,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        let s = (result as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
        #expect(s == "a[a]=1&a[c]=2&a[b][x]=1")
    }

    @Test("Encoder.encode deep fallback orders NSDictionary primitives before containers with encoder")
    func encoder_iterativeFallback_nsdictionaryPartition_withEncoder_depth512() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let data = NSDictionary(
            dictionary: [
                NSNumber(value: 2): NSDictionary(dictionary: ["x": 1]),
                NSNumber(value: 1): 1,
                NSNumber(value: 3): 3,
            ])
        let identity: ValueEncoder = { value, _, _ in String(describing: value ?? "") }

        let result = try Encoder.encode(
            data: data,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: identity,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        let s = (result as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
        #expect(s == "a[1]=1&a[3]=3&a[2][x]=1")
    }

    @Test("Encoder.encode deep fallback default-entry path returns empty parts for Undefined")
    func encoder_iterativeFallback_defaultEntryPath_undefined() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let result = try Encoder.encode(
            data: Undefined.instance,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        if let parts = result as? [Any] {
            #expect(parts.isEmpty)
        } else {
            Issue.record("Expected [Any] output for deep fallback Undefined path")
        }
    }

    @Test("Encoder.encode drops top-level NSNull when skipNulls is true")
    func encoder_skipNulls_topLevelNSNull() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let result = try Encoder.encode(
            data: NSNull(),
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: true,
            skipNulls: true,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 0
        )

        if let array = result as? [Any] {
            #expect(array.isEmpty)
        } else {
            Issue.record("Expected empty array for top-level NSNull + skipNulls, got: \(String(describing: result))")
        }
    }

    @Test("Encoder.encode deep fallback covers date and custom encoder branches")
    func encoder_iterativeFallback_dateAndCustomEncoder() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let epoch = Date(timeIntervalSince1970: 0)

        let dateResult = try Encoder.encode(
            data: epoch,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: nil,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        let dateString = dateResult as? String
        #expect(dateString == "a=1970-01-01T00:00:00.000Z")

        let custom: ValueEncoder = { value, _, _ in
            "[\(String(describing: value ?? ""))]"
        }
        let customResult = try Encoder.encode(
            data: 7,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: custom,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 512
        )
        #expect(customResult as? String == "[a]=[7]")
    }

    @Test("Encoder.encode nested NSDictionary branch partitions primitive and container keys")
    func encoder_nsdictionaryPartition_withEncoder() throws {
        let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        let data = NSDictionary(
            dictionary: [
                NSNumber(value: 2): NSDictionary(dictionary: ["x": 1]),
                NSNumber(value: 1): 1,
            ])
        let identity: ValueEncoder = { value, _, _ in String(describing: value ?? "") }

        let result = try Encoder.encode(
            data: data,
            undefined: false,
            sideChannel: sideChannel,
            prefix: "a",
            listFormat: .indices,
            commaRoundTrip: false,
            allowEmptyLists: false,
            strictNullHandling: false,
            skipNulls: false,
            encodeDotInKeys: false,
            encoder: identity,
            serializeDate: nil,
            sort: nil,
            filter: nil,
            allowDots: false,
            format: .rfc3986,
            formatter: nil,
            encodeValuesOnly: false,
            charset: .utf8,
            addQueryPrefix: false,
            depth: 1
        )
        let s = (result as? [Any])?.map { String(describing: $0) }.joined(separator: "&")
        #expect(s == "a[1]=1&a[2][x]=1")
    }

    @Test("Encoder.encode deep fallback preserves [String: Any] ordering parity")
    func encoder_iterativeFallback_preservesDictionaryOrderingParity() throws {
        let identity: ValueEncoder = { value, _, _ in String(describing: value ?? "") }
        let data: [String: Any] = [
            "b": ["x": 1],
            "a": 1,
            "c": 2,
        ]

        func encodeParts(depth: Int) throws -> [String] {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let result = try Encoder.encode(
                data: data,
                undefined: false,
                sideChannel: sideChannel,
                prefix: "a",
                listFormat: .indices,
                commaRoundTrip: false,
                allowEmptyLists: false,
                strictNullHandling: false,
                skipNulls: false,
                encodeDotInKeys: false,
                encoder: identity,
                serializeDate: nil,
                sort: nil,
                filter: nil,
                allowDots: false,
                format: .rfc3986,
                formatter: nil,
                encodeValuesOnly: false,
                charset: .utf8,
                addQueryPrefix: false,
                depth: depth
            )
            return (result as? [Any])?.map { String(describing: $0) } ?? []
        }

        let recursiveParts = try encodeParts(depth: 255)
        let fallbackParts = try encodeParts(depth: 256)
        let expected = ["a[a]=1", "a[c]=2", "a[b][x]=1"]
        #expect(recursiveParts == expected)
        #expect(fallbackParts == expected)
        #expect(recursiveParts == fallbackParts)
    }

    @Test("Encoder.encode deep fallback preserves NSDictionary ordering parity")
    func encoder_iterativeFallback_preservesNSDictionaryOrderingParity() throws {
        let data = NSDictionary(
            dictionary: [
                NSNumber(value: 2): NSDictionary(dictionary: ["x": 1]),
                NSNumber(value: 1): 1,
                NSNumber(value: 3): 3,
            ])

        func encodeParts(depth: Int) throws -> [String] {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let result = try Encoder.encode(
                data: data,
                undefined: false,
                sideChannel: sideChannel,
                prefix: "a",
                listFormat: .indices,
                commaRoundTrip: false,
                allowEmptyLists: false,
                strictNullHandling: false,
                skipNulls: false,
                encodeDotInKeys: false,
                encoder: nil,
                serializeDate: nil,
                sort: nil,
                filter: nil,
                allowDots: false,
                format: .rfc3986,
                formatter: nil,
                encodeValuesOnly: false,
                charset: .utf8,
                addQueryPrefix: false,
                depth: depth
            )
            return (result as? [Any])?.map { String(describing: $0) } ?? []
        }

        let recursiveParts = try encodeParts(depth: 255)
        let fallbackParts = try encodeParts(depth: 256)
        #expect(recursiveParts == fallbackParts)
    }

    #if canImport(Darwin)
        @Test("Encoder.encode emits empty list shell when allowEmptyLists is true")
        func encoder_allowEmptyLists_emitsBracket() throws {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let result = try Encoder.encode(
                data: [Any](),
                undefined: false,
                sideChannel: sideChannel,
                prefix: "items",
                listFormat: .indices,
                commaRoundTrip: false,
                allowEmptyLists: true,
                strictNullHandling: false,
                skipNulls: false,
                encodeDotInKeys: false,
                encoder: nil,
                serializeDate: nil,
                sort: nil,
                filter: nil,
                allowDots: false,
                format: .rfc3986,
                formatter: nil,
                encodeValuesOnly: false,
                charset: .utf8,
                addQueryPrefix: false,
                depth: 0
            )

            if let string = result as? String {
                #expect(string == "items[]")
            } else {
                Issue.record("Expected string output for empty list, got: \(String(describing: result))")
            }
        }
    #endif

    #if DEBUG && os(macOS)
        @MainActor
        @Test("encode: very deep nested maps do not overflow stack")
        func encode_veryDeepMaps_noStackOverflow() throws {
            let depth = 1_700

            var leaf: Any? = ["v": "x"] as [String: Any]
            for _ in 0..<depth {
                leaf = ["p": leaf as Any]
            }

            let encoded = try Qs.encode(["root": leaf as Any], options: .init(encode: false))
            #expect(encoded.hasPrefix("root"))
            #expect(encoded.hasSuffix("=x"))
        }
    #endif

    #if canImport(Darwin)
        @Test("Encoder.encode handles comma list format round-tripping single-element arrays")
        func encoder_commaRoundTrip_adjustsPrefix() throws {
            let sideChannel = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
            let result = try Encoder.encode(
                data: ["only"],
                undefined: false,
                sideChannel: sideChannel,
                prefix: "flags",
                listFormat: .comma,
                commaRoundTrip: true,
                allowEmptyLists: false,
                strictNullHandling: false,
                skipNulls: false,
                encodeDotInKeys: false,
                encoder: nil,
                serializeDate: nil,
                sort: nil,
                filter: nil,
                allowDots: false,
                format: .rfc3986,
                formatter: nil,
                encodeValuesOnly: false,
                charset: .utf8,
                addQueryPrefix: false,
                depth: 0
            )

            if let string = result as? String {
                #expect(string == "flags[]=only")
            } else if let parts = result as? [Any], let first = parts.first as? String {
                #expect(first == "flags[]=only")
            } else {
                Issue.record("Unexpected type for comma round-trip branch: \(String(describing: result))")
            }
        }
    #endif
}

// Linux-only: Validate NSMapTable facade basic behavior for weakToWeakObjects
#if os(Linux)
    @Test("Linux shim: NSMapTable weakToWeakObjects behaves")
    func linuxShim_NSMapTable_weak_basic() throws {
        final class Foo: NSObject {}
        let side = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()
        do {
            let k = Foo()
            let v = Foo()
            side.setObject(v, forKey: k)
            #expect(side.object(forKey: k) != nil)
        }
        // Post-scope, both key and value had only weak references in the table.
        // We can’t force ARC to collect deterministically; existence checks here are best‑effort.
        #expect(true)
    }

    @Test("Linux shim: NSMapTable strongToStrongObjects retains key/value strongly")
    func linuxShim_NSMapTable_strong_retainSemantics() throws {
        final class Foo: NSObject {}

        weak var weakKey: Foo?
        weak var weakValue: Foo?

        let table = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
        do {
            let key = Foo()
            let value = Foo()
            weakKey = key
            weakValue = value

            table.setObject(value, forKey: key)
            #expect(table.object(forKey: key) === value)
        }

        #expect(weakKey != nil)
        #expect(weakValue != nil)
        if let retainedKey = weakKey {
            #expect(table.object(forKey: retainedKey) != nil)
        } else {
            Issue.record("Expected key to be strongly retained by strongToStrongObjects")
        }
    }
#endif

// MARK: - Helpers

// Helper used by tests in this file
private struct CustomObject {
    let prop: String
    init(_ prop: String) { self.prop = prop }
    subscript(_ key: String) -> Any? { key == "prop" ? prop : nil }
}

final class _Recorder: @unchecked Sendable {
    private var items: [String] = []
    private let lock = NSLock()

    func add(_ s: String) {
        lock.lock()
        items.append(s)
        lock.unlock()
    }
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty
    }
}

// Put this test helper somewhere in your test target.
private func multisetParts(_ qs: String) -> [String: Int] {
    var bag: [String: Int] = [:]
    for p in qs.split(separator: "&") {
        let s = String(p)
        bag[s, default: 0] += 1
    }
    return bag
}

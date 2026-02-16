#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import OrderedCollections

    @testable import QsObjC
    @testable import QsSwift

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    @Suite("objc-model-coverage")
    struct ObjCModelCoverageTests {

        @Test("Bridged enums expose Swift parity")
        func enumBridges() {
            #expect(DecodeKindObjC.key.swift == .key)
            #expect(DecodeKindObjC(.value) == .value)
            #expect(DecodeKindObjC.value.description == "value")

            #expect(DuplicatesObjC.combine.swift == .combine)
            #expect(DuplicatesObjC.first.description == "first")
            #expect(DuplicatesObjC.last.swift == .last)

            #expect(FormatObjC.rfc3986.swift == .rfc3986)
            #expect(FormatObjC.rfc1738.description == "rfc1738")

            #expect(ListFormatObjC.brackets.swift == .brackets)
            #expect(ListFormatObjC.indices.description == "indices")
            #expect(ListFormatObjC.repeatKey.swift == .repeatKey)
            #expect(ListFormatObjC.comma.swift == .comma)
        }

        @Test("DecodeErrorObjC surfaces NSError metadata")
        func decodeErrorBridging() {
            let opts = DecodeOptionsObjC().with {
                $0.parameterLimit = 1
                $0.throwOnLimitExceeded = true
            }

            var err: NSError?
            let output = QsBridge.decode("a=1&b=2" as NSString, options: opts, error: &err)
            #expect(output == nil, Comment("Parameter limit exceedance should return nil result"))
            #expect(err != nil, Comment("Expected NSError for parameter limit"))
            guard let error = err else { return }

            #expect(error.domain == DecodeErrorInfoObjC.domain)
            #expect(DecodeErrorObjC.kind(from: error) == .parameterLimitExceeded)
            #expect(DecodeErrorObjC.limit(from: error) == 1)

            let depthOpts = DecodeOptionsObjC().with {
                $0.depth = 1
                $0.strictDepth = true
                $0.throwOnLimitExceeded = true
            }

            err = nil
            let depthOutput = QsBridge.decode("a[b][c]=d" as NSString, options: depthOpts, error: &err)
            #expect(depthOutput == nil, Comment("Strict depth should throw instead of returning a value"))
            #expect(err != nil, Comment("Expected depth error"))

            if let depthError = err {
                #expect(DecodeErrorObjC.kind(from: depthError) == .depthExceeded)
                #expect(DecodeErrorObjC.maxDepth(from: depthError) == 1)
            }
        }

        @Test("DecodeErrorObjC returns nil for mismatched domain")
        func decodeErrorNilCases() {
            let error = NSError(domain: "other", code: 1, userInfo: [:])
            #expect(DecodeErrorObjC.kind(from: error) == nil)
            #expect(DecodeErrorObjC.limit(from: error) == nil)
            #expect(DecodeErrorObjC.maxDepth(from: error) == nil)
        }

        @Test("EncodeErrorObjC identifies cyclic graphs")
        func encodeErrorBridging() {
            let dict = NSMutableDictionary()
            dict["self"] = dict

            var err: NSError?
            let encoded = QsBridge.encode(dict, options: nil, error: &err)
            #expect(encoded == nil)
            guard let error = err else {
                Issue.record("Expected encode NSError")
                return
            }

            #expect(error.domain == EncodeErrorInfoObjC.domain)
            #expect(EncodeErrorObjC.kind(from: error) == .cyclicObject)
            #expect(EncodeErrorObjC.isCyclicObject(error))
        }

        @Test("EncodeErrorObjC returns nil for unrelated errors")
        func encodeErrorNilCases() {
            let error = NSError(domain: "other", code: 99)
            #expect(EncodeErrorObjC.kind(from: error) == nil)
            #expect(EncodeErrorObjC.isCyclicObject(error) == false)
        }

        @Test("DecodeErrorObjC reads userInfo values")
        func decodeErrorUserInfo() {
            let userInfo: [String: Any] = [
                DecodeErrorInfoObjC.limitKey: 5,
                DecodeErrorInfoObjC.maxDepthKey: 2,
            ]
            let mock = NSError(
                domain: DecodeErrorInfoObjC.domain,
                code: DecodeErrorCodeObjC.listLimitExceeded.rawValue,
                userInfo: userInfo
            )

            #expect(DecodeErrorObjC.kind(from: mock) == .listLimitExceeded)
            #expect(DecodeErrorObjC.limit(from: mock) == 5)
            #expect(DecodeErrorObjC.maxDepth(from: mock) == 2)
        }

        @Test("DecodeErrorCodeObjC descriptions mirror Swift cases")
        func decodeErrorCode_descriptions() {
            #expect(DecodeErrorCodeObjC.parameterLimitNotPositive.description == "parameterLimitNotPositive")
            #expect(DecodeErrorCodeObjC.parameterLimitExceeded.description == "parameterLimitExceeded")
            #expect(DecodeErrorCodeObjC.listLimitExceeded.description == "listLimitExceeded")
            #expect(DecodeErrorCodeObjC.depthExceeded.description == "depthExceeded")
        }

        @Test("EncodeErrorCodeObjC description mirrors Swift case")
        func encodeErrorCode_description() {
            #expect(EncodeErrorCodeObjC.cyclicObject.description == "cyclicObject")
        }

        @Test("DelimiterObjC wraps string and regex delimiters")
        func delimiterBridging() {
            let stringDelimiter = DelimiterObjC(string: "&")
            #expect(stringDelimiter.swift.split(input: "a&b") == ["a", "b"])

            let regexDelimiter = DelimiterObjC(regexPattern: #"\s*[,;]\s*"#)
            #expect(regexDelimiter != nil)
            #expect(regexDelimiter?.swift.split(input: "a ; b, c") == ["a", "b", "c"])

            let invalid = DelimiterObjC(regexPattern: "[")
            #expect(invalid == nil)

            #expect(DelimiterObjC.commaOrSemicolon.swift.split(input: "x;y") == ["x", "y"])
        }

        @Test("DecodedMapObjC round-trips Swift DecodedMap")
        func decodedMapBridging() {
            let swiftMap = DecodedMap(["a": "b"])
            let objcMap = DecodedMapObjC(swift: swiftMap)
            #expect((objcMap.value["a"] as? String) == "b")
            #expect(objcMap.swift.value["a"] as? String == "b")
        }

        @Test("DecodeOptionsObjC bridges core properties")
        func decodeOptionsSwiftBridgeProperties() {
            let opts = DecodeOptionsObjC().with {
                $0.allowDots = true
                $0.decodeDotInKeys = true
                $0.allowEmptyLists = true
                $0.allowSparseLists = true
                $0.listLimit = 2
                $0.charset = String.Encoding.isoLatin1.rawValue
                $0.charsetSentinel = true
                $0.comma = true
                $0.delimiter = .commaOrSemicolon
                $0.depth = 1
                $0.parameterLimit = 2
                $0.duplicates = .last
                $0.ignoreQueryPrefix = true
                $0.interpretNumericEntities = true
                $0.parseLists = false
                $0.strictDepth = true
                $0.strictNullHandling = true
                $0.throwOnLimitExceeded = true
            }

            let swift = opts.swift
            #expect(swift.getAllowDots)
            #expect(swift.getDecodeDotInKeys)
            #expect(swift.allowEmptyLists)
            #expect(swift.allowSparseLists)
            #expect(swift.listLimit == 2)
            #expect(swift.charset == .isoLatin1)
            #expect(swift.charsetSentinel)
            #expect(swift.comma)
            #expect(swift.delimiter.split(input: "a ; b").count == 2)
            #expect(swift.depth == 1)
            #expect(swift.parameterLimit == 2)
            #expect(swift.duplicates == .last)
            #expect(swift.ignoreQueryPrefix)
            #expect(swift.interpretNumericEntities)
            #expect(swift.parseLists == false)
            #expect(swift.strictDepth)
            #expect(swift.strictNullHandling)
            #expect(swift.throwOnLimitExceeded)
        }

        @Test("DecodeOptionsObjC sanitizes invalid values before bridging")
        func decodeOptionsSanitization() {
            let opts = DecodeOptionsObjC().with {
                $0.allowDots = false
                $0.decodeDotInKeys = true
                $0.charset = String.Encoding.shiftJIS.rawValue
                $0.parameterLimit = 0
                $0.depth = -5
            }

            let swift = opts.swift
            #expect(swift.getAllowDots)
            #expect(swift.getDecodeDotInKeys)
            #expect(swift.charset == .utf8)
            #expect(swift.parameterLimit == 1)
            #expect(swift.depth == 0)
        }

        @Test("DecodeOptionsObjC bridges decoder blocks in priority order")
        func decodeOptionsCustomBlocks() {
            var seenKinds: [Int] = []
            let opts = DecodeOptionsObjC()
            opts.decoderBlock = { token, charset, kind in
                seenKinds.append(kind?.intValue ?? -1)
                guard let token else { return nil }
                let utf8Raw = Int(String.Encoding.utf8.rawValue)
                let suffix = (charset?.intValue ?? utf8Raw) == utf8Raw ? "!" : "?"
                return ((token as String) + suffix) as NSString
            }

            let swiftDecoder = opts.swift.decoder
            let keyResult = swiftDecoder?("a", .utf8, .key) as? String
            let valueResult = swiftDecoder?("b", .utf8, .value) as? String
            #expect(seenKinds == [0, 1])
            #expect(keyResult == "a!")
            #expect(valueResult == "b!")

            let valueOnly = DecodeOptionsObjC()
            valueOnly.valueDecoderBlock = { token, _ in
                (token as String?)?.uppercased()
            }
            let swiftValueDecoder = valueOnly.swift.decoder
            #expect(swiftValueDecoder?("c", .isoLatin1, nil) as? String == "C")

            let legacy = DecodeOptionsObjC()
            legacy.legacyDecoderBlock = { token, _ in
                token?.appending("?")
            }
            let swiftLegacy = legacy.swift.legacyDecoder
            #expect(swiftLegacy?("e", .utf8) as? String == "e?")
        }

        @Test("EncodeOptionsObjC bridges configuration and custom blocks")
        func encodeOptionsSwiftBridgeAndBlocks() {
            let opts = EncodeOptionsObjC().with {
                $0.addQueryPrefix = true
                $0.allowDots = true
                $0.encodeDotInKeys = true
                $0.allowEmptyLists = true
                $0.charset = String.Encoding.isoLatin1.rawValue
                $0.charsetSentinel = true
                $0.delimiter = ";"
                $0.encode = true
                $0.encodeValuesOnly = true
                $0.format = .rfc1738
                $0.indices = NSNumber(value: false)
                $0.listFormat = .brackets
                $0.skipNulls = true
                $0.strictNullHandling = true
                $0.commaRoundTrip = true
                $0.sortKeysCaseInsensitively = true
                $0.filter = FilterObjC.excluding { $0 == "skip" }
                $0.valueEncoderBlock = { value, _, _ in
                    if let string = value as? String { return (string + "!") as NSString }
                    return "encoded" as NSString
                }
                $0.dateSerializerBlock = { date in
                    "d_\(Int(date.timeIntervalSince1970))" as NSString
                }
                $0.sortComparatorBlock = { lhs, rhs in
                    let sa = String(describing: lhs ?? "")
                    let sb = String(describing: rhs ?? "")
                    return sa.compare(sb).rawValue
                }
            }

            let swift = opts.swift
            #expect(swift.addQueryPrefix)
            #expect(swift.getAllowDots)
            #expect(swift.getListFormat == .brackets)
            #expect(swift.charset == .isoLatin1)
            #expect(swift.charsetSentinel)
            #expect(swift.delimiter == ";")
            #expect(swift.encode)
            #expect(swift.encodeDotInKeys)
            #expect(swift.encodeValuesOnly)
            #expect(swift.format == .rfc1738)
            #expect(swift.skipNulls)
            #expect(swift.strictNullHandling)
            #expect(swift.commaRoundTrip == true)
            #expect(swift.sort != nil)

            let input: NSDictionary = [
                "b": "beta",
                "A": "alpha",
                "skip": "omitted",
                "date": Date(timeIntervalSince1970: 123),
                "list": ["x", "y"],
            ]

            var err: NSError?
            guard let encoded = QsBridge.encode(input, options: opts, error: &err) else {
                Issue.record("Expected encoded string")
                return
            }

            let output = encoded as String
            #expect(output.hasPrefix("?"))
            #expect(!output.contains("skip"))
            #expect(output.contains("beta!"))
            #expect(output.contains("alpha!"))
            #expect(output.contains("d_123!"))
            #expect(output.contains("list[]"))
            #expect(output.contains(";"))
        }

        @Test("EncodeOptionsObjC listFormatBoxed getter and setter round-trip")
        func encodeOptions_listFormatBoxedRoundTrip() {
            let opts = EncodeOptionsObjC()

            #expect(opts.listFormat == nil)
            #expect(opts.listFormatBoxed == nil)

            opts.listFormatBoxed = NSNumber(value: ListFormatObjC.comma.rawValue)
            #expect(opts.listFormat == .comma)
            #expect(opts.listFormatBoxed?.intValue == ListFormatObjC.comma.rawValue)

            opts.listFormat = .indices
            #expect(opts.listFormatBoxed?.intValue == ListFormatObjC.indices.rawValue)

            opts.listFormatBoxed = NSNumber(value: 999)
            #expect(opts.listFormat == nil)
            #expect(opts.listFormatBoxed == nil)
        }

        @Test("EncodeOptionsObjC sanitizes invalid charset before bridging")
        func encodeOptionsSanitization() {
            let opts = EncodeOptionsObjC().with {
                $0.charset = String.Encoding.shiftJIS.rawValue
            }
            #expect(opts.swift.charset == .utf8)
        }

        @Test("FilterObjC factories wrap Swift filters")
        func filterObjCFactories() {
            let functionFilter = FilterObjC.function(
                FunctionFilterObjC { key, value in
                    key == "drop" ? UndefinedObjC() : value
                })
            let iterable = FilterObjC.iterable(IterableFilterObjC(iterable: ["keep", 1]))
            let excluding = FilterObjC.excluding { $0 == "omit" }
            let including = FilterObjC.including { $0 == "keep" }
            let keys = FilterObjC.keys(["name"])
            let indices = FilterObjC.indices([0, 2])
            let mixed = FilterObjC.mixed(["name", 3])

            // Bridge through EncodeOptions to ensure filters integrate correctly
            let opts = EncodeOptionsObjC()
            opts.filter = functionFilter
            let dict: NSDictionary = ["drop": "x", "keep": "y"]
            let encoded = QsBridge.encode(dict, options: opts, error: nil)! as String
            #expect(!encoded.contains("drop"))

            // Confirm iterable-style filters carry their payloads
            #expect((iterable.swift as? IterableFilter)?.iterable.count == 2)
            #expect((excluding.swift as? FunctionFilter) != nil)
            #expect((including.swift as? FunctionFilter) != nil)
            #expect((keys.swift as? IterableFilter)?.iterable.first as? String == "name")
            #expect((indices.swift as? IterableFilter)?.iterable.first as? Int == 0)
            #expect((mixed.swift as? IterableFilter)?.iterable.last as? Int == 3)
        }

        @Test("FunctionFilterObjC preserves nested traversal when returning value")
        func functionFilterObjCPreservesNestedTraversal() {
            let date = Date(timeIntervalSince1970: 0.123)
            let input: NSDictionary = [
                "a": "b",
                "e": ["f": date, "g": [2]],
            ]

            let ff = FunctionFilterObjC { key, value in
                if key == "e[f]" {
                    guard let date = value as? Date else { return value }
                    return NSNumber(value: Int((date.timeIntervalSince1970 * 1000).rounded()))
                }
                if key == "e[g][0]", let n = value as? NSNumber {
                    return NSNumber(value: n.intValue * 2)
                }
                return value
            }

            let opts = EncodeOptionsObjC()
            opts.encode = false
            opts.filter = .function(ff)

            let encoded = QsBridge.encode(input, options: opts, error: nil) as String?
            #expect(encoded != nil)
            let parts = Set((encoded ?? "").split(separator: "&").map(String.init))
            #expect(parts.contains("a=b"))
            #expect(parts.contains("e[f]=123"))
            #expect(parts.contains("e[g][0]=4"))
        }

        @Test("bridgeUndefinedPreservingOrder normalizes Swift dictionaries and arrays")
        func bridgeUndefined_preservesSwiftContainers() {
            let swiftDict: [String: Any] = [
                "scalar": UndefinedObjC(),
                "array": [UndefinedObjC(), "value"],
            ]

            if let bridged = QsBridge.bridgeUndefinedPreservingOrder(swiftDict)
                as? OrderedDictionary<String, Any>
            {
                #expect(bridged["scalar"] is Undefined)
                let array = bridged["array"] as? [Any]
                #expect(array?.first is Undefined)
                #expect(array?.last as? String == "value")
            } else {
                Issue.record("Expected OrderedDictionary when bridging Swift dictionary")
            }

            let swiftArray: [Any] = [
                UndefinedObjC(),
                ["nested": UndefinedObjC()],
            ]

            if let bridgedArray = QsBridge.bridgeUndefinedPreservingOrder(swiftArray) as? [Any] {
                #expect(bridgedArray.first is Undefined)
                if let nested = bridgedArray.last as? OrderedDictionary<String, Any> {
                    #expect(nested["nested"] is Undefined)
                } else if let nested = bridgedArray.last as? [String: Any] {
                    #expect(nested["nested"] is Undefined)
                } else {
                    Issue.record("Expected nested container when bridging Swift array")
                }
            } else {
                Issue.record("Expected bridged Swift array")
            }
        }
    }
#endif

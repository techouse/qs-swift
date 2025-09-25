#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation

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
                $0.allowDots = false
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

        @Test("FilterObjC factories wrap Swift filters")
        func filterObjCFactories() {
            let functionFilter = FilterObjC.function(FunctionFilterObjC { key, value in
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
    }
#endif

// swiftlint:disable file_length
import Foundation
import OrderedCollections

private protocol _AnyOptional {
    var _wrappedAny: Any? { get }
}

extension Optional: _AnyOptional {
    fileprivate var _wrappedAny: Any? {
        switch self {
        case .some(let wrapped):
            return wrapped
        case .none:
            return nil
        }
    }
}

/// A helper object for encoding data into a query string format.
internal enum Encoder {
    // MARK: - Encode

    @usableFromInline
    static func encode(
        data: Any?,
        undefined: Bool,
        sideChannel: NSMapTable<AnyObject, AnyObject>,
        prefix: String? = nil,
        generateArrayPrefix: ListFormatGenerator? = nil,
        listFormat: ListFormat = .indices,
        commaRoundTrip: Bool = false,
        commaCompactNulls: Bool = false,
        allowEmptyLists: Bool = false,
        strictNullHandling: Bool = false,
        skipNulls: Bool = false,
        encodeDotInKeys: Bool = false,
        encoder: ValueEncoder? = nil,
        serializeDate: DateSerializer? = nil,
        sort: Sorter? = nil,
        filter: Filter? = nil,
        allowDots: Bool = false,
        format: Format = .rfc3986,
        formatter: Formatter? = nil,
        encodeValuesOnly: Bool = false,
        charset: String.Encoding = .utf8,
        addQueryPrefix: Bool = false,
        depth: Int = 0
    ) throws -> Any {
        // Kept for API compatibility: passed from Qs+Encode and direct tests that still exercise this signature.
        // Preserve until those call sites and iterative path-tracking expectations are updated in one refactor.
        _ = sideChannel

        let effectiveGenerator = generateArrayPrefix ?? listFormat.generator
        let rootConfig = EncodeConfig(
            generateArrayPrefix: effectiveGenerator,
            listFormat: listFormat,
            hasCustomGenerator: generateArrayPrefix != nil,
            commaRoundTrip: commaRoundTrip,
            commaCompactNulls: commaCompactNulls,
            allowEmptyLists: allowEmptyLists,
            strictNullHandling: strictNullHandling,
            skipNulls: skipNulls,
            encodeDotInKeys: encodeDotInKeys,
            encoder: encoder,
            serializeDate: serializeDate,
            sort: sort,
            filter: filter,
            allowDots: allowDots,
            format: format,
            formatter: formatter ?? format.formatter,
            encodeValuesOnly: encodeValuesOnly,
            charset: charset
        )

        let rootPrefix = prefix ?? (addQueryPrefix ? "?" : "")
        let rootIsContainer = isContainer(data)

        if let fast = try encodeLinearChainIfEligible(
            data: data, undefined: undefined, prefix: rootPrefix, config: rootConfig)
        {
            return rootIsContainer ? [fast] : fast
        }

        var stack: [EncodeFrame] = [
            EncodeFrame(
                object: data,
                undefined: undefined,
                path: KeyPathNode.fromMaterialized(rootPrefix),
                config: rootConfig,
                depth: depth,
            )
        ]

        var activeContainers = Set<ObjectIdentifier>()
        var lastResult: Any?
        var lastBracketKey: String?
        var lastBracketSegment = ""
        var lastDotKey: String?
        var lastDotSegment = ""

        @inline(__always)
        func bracketSegment(for encodedKey: String) -> String {
            if lastBracketKey == encodedKey {
                return lastBracketSegment
            }
            let segment = "[\(encodedKey)]"
            lastBracketKey = encodedKey
            lastBracketSegment = segment
            return segment
        }

        @inline(__always)
        func dotSegment(for encodedKey: String) -> String {
            if lastDotKey == encodedKey {
                return lastDotSegment
            }
            let segment = ".\(encodedKey)"
            lastDotKey = encodedKey
            lastDotSegment = segment
            return segment
        }

        func finishFrame(_ result: Any) {
            let completed = stack.removeLast()
            if let tracked = completed.trackedContainerID {
                activeContainers.remove(tracked)
            }
            lastResult = result
        }

        while let frame = stack.last {
            let config = frame.config

            switch frame.phase {
            case .start:
                var obj = frame.object
                var pathText: String?

                func materializedPath() -> String {
                    if let pathText {
                        return pathText
                    }
                    let value = frame.path.materialize()
                    pathText = value
                    return value
                }

                if let containerID = containerIdentity(obj) {
                    if activeContainers.contains(containerID) {
                        throw EncodeError.cyclicObject
                    }
                    activeContainers.insert(containerID)
                    frame.trackedContainerID = containerID
                }

                if let functionFilter = config.filter as? FunctionFilter {
                    let transformed = functionFilter.function(materializedPath(), obj)
                    // Intentional: filters may edit existing containers, but must not promote a primitive into a container.
                    if isContainer(obj) {
                        obj = transformed
                    } else if transformed == nil || !isContainer(transformed) {
                        obj = transformed
                    }
                }

                if let date = obj as? Date {
                    obj = config.serializeDate?(date) ?? iso8601().string(from: date)
                } else if config.isCommaListFormat, let iterable = obj as? [Any] {
                    obj = iterable.map { element -> Any in
                        if let date = element as? Date {
                            return config.serializeDate?(date) ?? iso8601().string(from: date)
                        }
                        return element
                    }
                }

                if !frame.undefined && obj == nil {
                    if config.strictNullHandling {
                        if let enc = config.encoder, !config.encodeValuesOnly {
                            finishFrame(enc(materializedPath(), config.charset, config.format))
                        } else {
                            finishFrame(materializedPath())
                        }
                        continue
                    }
                    obj = ""
                }

                if config.skipNulls, obj is NSNull {
                    finishFrame([Any]())
                    continue
                }

                if obj is NSNull {
                    if config.strictNullHandling {
                        if let enc = config.encoder, !config.encodeValuesOnly {
                            finishFrame(config.formatter.apply(enc(materializedPath(), nil, nil)))
                        } else {
                            finishFrame(config.formatter.apply(materializedPath()))
                        }
                    } else if let enc = config.encoder {
                        let keyPart = config.encodeValuesOnly ? materializedPath() : enc(materializedPath(), nil, nil)
                        let valPart = enc("", nil, nil)
                        finishFrame("\(config.formatter.apply(keyPart))=\(config.formatter.apply(valPart))")
                    } else {
                        finishFrame("\(config.formatter.apply(materializedPath()))=")
                    }
                    continue
                }

                let normalizedScalar: Any? = {
                    guard let some = obj else { return nil }
                    return unwrapOptional(some) ?? some
                }()

                if Utils.isNonNullishPrimitive(normalizedScalar, skipNulls: config.skipNulls)
                    || normalizedScalar is Data
                {
                    if let enc = config.encoder {
                        let keyPart = config.encodeValuesOnly ? materializedPath() : enc(materializedPath(), nil, nil)
                        let valPart = enc(normalizedScalar, nil, nil)
                        finishFrame("\(config.formatter.apply(keyPart))=\(config.formatter.apply(valPart))")
                    } else {
                        finishFrame(
                            "\(config.formatter.apply(materializedPath()))=\(config.formatter.apply(describe(normalizedScalar, charset: config.charset)))"
                        )
                    }
                    continue
                }

                if frame.undefined {
                    finishFrame([Any]())
                    continue
                }

                var seqList = arrayize(obj)
                var commaEffectiveLength: Int?
                let nextKeyState: EncodeKeyState

                if config.isCommaListFormat, var elements = seqList {
                    if config.commaCompactNulls {
                        elements = elements.compactMap { element in
                            if element is NSNull {
                                return nil
                            }
                            if isOptional(element) {
                                guard let unwrapped = unwrapOptional(element) else {
                                    return nil
                                }
                                if unwrapped is NSNull {
                                    return nil
                                }
                                return unwrapped
                            }
                            return element
                        }
                        seqList = elements
                        obj = elements
                    }

                    if config.encodeValuesOnly, let enc = config.encoder {
                        elements = elements.map { value in
                            enc(describeForComma(value, charset: config.charset), nil, nil)
                        }
                        seqList = elements
                        obj = elements
                    }

                    commaEffectiveLength = elements.count

                    if !elements.isEmpty {
                        let joined = elements.map { describeForComma($0, charset: config.charset) }.joined(
                            separator: ",")
                        let valueForJoin: Any = joined.isEmpty ? (config.strictNullHandling ? NSNull() : "") : joined
                        nextKeyState = .single(["value": valueForJoin])
                    } else {
                        nextKeyState = .single(["value": Undefined.instance])
                    }
                } else if let iterableFilter = config.filter as? IterableFilter {
                    nextKeyState = keyState(from: iterableFilter.iterable)
                } else {
                    nextKeyState = objectKeyState(for: obj, seqList: seqList, config: config, depth: frame.depth)
                }

                let pathForChildren = config.encodeDotInKeys ? frame.path.asDotEncoded() : frame.path
                let shouldAppendRoundTripMarker =
                    config.commaRoundTrip
                    && seqList != nil
                    && (config.isCommaListFormat && commaEffectiveLength != nil
                        ? commaEffectiveLength == 1
                        : (seqList?.count == 1))
                let adjustedPath = shouldAppendRoundTripMarker ? pathForChildren.append("[]") : pathForChildren

                if config.allowEmptyLists, let seqList, seqList.isEmpty {
                    finishFrame(adjustedPath.append("[]").materialize())
                    continue
                }

                frame.object = obj
                frame.keyState = nextKeyState
                frame.index = 0
                frame.seqList = seqList
                frame.commaEffectiveLength = commaEffectiveLength
                frame.adjustedPath = adjustedPath
                frame.phase = .iterate

            case .iterate:
                let key: Any
                switch frame.keyState {
                case .none:
                    finishFrame(frame.values.asArray())
                    continue
                case .single(let only):
                    if frame.index > 0 {
                        finishFrame(frame.values.asArray())
                        continue
                    }
                    key = only
                    frame.index = 1
                case .many(let keys):
                    if frame.index >= keys.count {
                        finishFrame(frame.values.asArray())
                        continue
                    }
                    key = keys[frame.index]
                    frame.index += 1
                }

                let value: Any?
                let valueUndefined: Bool

                if let keyDict = key as? [String: Any], let keyValue = keyDict["value"], !(keyValue is Undefined) {
                    value = keyValue
                    valueUndefined = false
                } else {
                    (value, valueUndefined) = resolveValue(from: frame.object, seqList: frame.seqList, key: key)
                }

                if config.skipNulls && (value == nil || value is NSNull) {
                    continue
                }

                let rawKey: String
                if let stringKey = key as? String {
                    rawKey = stringKey
                } else if let intKey = key as? Int {
                    rawKey = String(intKey)
                } else {
                    rawKey = String(describing: key)
                }
                let encodedKey: String = {
                    if config.allowDots && config.encodeDotInKeys {
                        return rawKey.replacingOccurrences(of: ".", with: "%2E")
                    }
                    return rawKey
                }()

                let isCommaSentinel = (key as? [String: Any])?.keys.contains("value") == true
                guard let adjustedPath = frame.adjustedPath else {
                    preconditionFailure(
                        "Invariant violation: EncodeFrame.adjustedPath must be set before .iterate phase")
                }

                let childPath: KeyPathNode
                if isCommaSentinel && config.isCommaListFormat {
                    childPath = adjustedPath
                } else if frame.seqList != nil {
                    if !config.hasCustomGenerator {
                        switch config.listFormat {
                        case .indices:
                            childPath = adjustedPath.append(bracketSegment(for: encodedKey))
                        case .brackets:
                            childPath = adjustedPath.append("[]")
                        case .repeatKey, .comma:
                            childPath = adjustedPath
                        }
                    } else {
                        childPath = KeyPathNode.fromMaterialized(
                            config.generateArrayPrefix(adjustedPath.materialize(), encodedKey))
                    }
                } else if config.allowDots {
                    childPath = adjustedPath.append(dotSegment(for: encodedKey))
                } else {
                    childPath = adjustedPath.append(bracketSegment(for: encodedKey))
                }

                let childEncoder: ValueEncoder?
                if config.isCommaListFormat && config.encodeValuesOnly && frame.seqList != nil {
                    childEncoder = nil
                } else {
                    childEncoder = config.encoder
                }

                frame.phase = .awaitChild
                stack.append(
                    EncodeFrame(
                        object: value,
                        undefined: valueUndefined,
                        path: childPath,
                        config: config.withEncoder(childEncoder),
                        depth: frame.depth + 1
                    )
                )

            case .awaitChild:
                if case .single = frame.keyState {
                    if let encodedList = lastResult as? [Any] {
                        finishFrame(encodedList)
                    } else if let encoded = lastResult {
                        finishFrame([encoded])
                    } else {
                        finishFrame([Any]())
                    }
                    continue
                }

                if let encodedList = lastResult as? [Any] {
                    frame.values.append(contentsOf: encodedList)
                } else if let encoded = lastResult {
                    frame.values.append(encoded)
                }
                frame.phase = .iterate
            }
        }

        return lastResult ?? [Any]()
    }
}

extension QsSwift.Encoder {
    // MARK: - Helpers

    private static func encodeLinearChainIfEligible(
        data: Any?,
        undefined: Bool,
        prefix: String,
        config: EncodeConfig
    ) throws -> String? {
        guard !undefined else { return nil }
        guard config.encoder == nil else { return nil }
        guard config.sort == nil else { return nil }
        guard config.filter == nil else { return nil }
        guard !config.allowDots, !config.encodeDotInKeys else { return nil }
        guard !config.isCommaListFormat else { return nil }
        guard !config.commaRoundTrip, !config.commaCompactNulls else { return nil }
        guard !config.allowEmptyLists else { return nil }
        guard !config.strictNullHandling else { return nil }
        guard !config.skipNulls else { return nil }
        guard !config.encodeValuesOnly else { return nil }
        guard !config.hasCustomGenerator else { return nil }
        guard config.listFormat == .indices else { return nil }

        var current: Any? = data
        var path = prefix
        var seen = Set<ObjectIdentifier>()

        while true {
            if current == nil {
                return "\(config.formatter.apply(path))="
            }

            if let date = current as? Date {
                current = config.serializeDate?(date) ?? iso8601().string(from: date)
                continue
            }

            if let object = current, type(of: object) is AnyClass {
                if object is NSNull {
                    return "\(config.formatter.apply(path))="
                }

                if let dict = object as? NSDictionary {
                    let id = ObjectIdentifier(dict)
                    if seen.contains(id) {
                        throw EncodeError.cyclicObject
                    }
                    seen.insert(id)

                    guard dict.count == 1 else { return nil }
                    guard let key = dict.allKeys.first else { return nil }
                    path.append("[")
                    path.append(String(describing: key))
                    path.append("]")
                    current = dict[key]
                    continue
                }
            }

            switch current {
            case let map as [String: Any]:
                guard map.count == 1, let (key, next) = map.first else { return nil }
                path.append("[")
                path.append(key)
                path.append("]")
                current = next

            case let ordered as OrderedDictionary<String, Any>:
                guard ordered.count == 1, let key = ordered.keys.first, let next = ordered[key] else {
                    return nil
                }
                path.append("[")
                path.append(key)
                path.append("]")
                current = next

            default:
                let normalizedScalar: Any? = {
                    guard let some = current else { return nil }
                    return unwrapOptional(some) ?? some
                }()

                if Utils.isNonNullishPrimitive(normalizedScalar) || normalizedScalar is Data {
                    return
                        "\(config.formatter.apply(path))=\(config.formatter.apply(describe(normalizedScalar, charset: config.charset)))"
                }

                return nil
            }
        }
    }

    @inline(__always)
    private static func keyState(from keys: [Any]) -> EncodeKeyState {
        switch keys.count {
        case 0:
            return .none
        case 1:
            return .single(keys[0])
        default:
            return .many(keys)
        }
    }

    private static func resolveValue(from object: Any?, seqList: [Any]?, key: Any) -> (Any?, Bool) {
        if let seqList {
            guard let idx = key as? Int, idx >= 0, idx < seqList.count else {
                return (nil, true)
            }
            return (seqList[idx], false)
        }

        switch object {
        case let od as OrderedDictionary<String, Any>:
            guard let keyString = key as? String else {
                return (nil, true)
            }
            guard let raw = od[keyString] else {
                return (nil, true)
            }
            return (unwrapOptional(raw) ?? raw, false)

        case let dict as [String: Any]:
            guard let keyString = key as? String else {
                return (nil, true)
            }
            guard let raw = dict[keyString] else {
                return (nil, true)
            }
            return (unwrapOptional(raw) ?? raw, false)

        case let nd as NSDictionary:
            let value = nd[key]
            return (value, value == nil)

        default:
            return (nil, true)
        }
    }

    private static func objectKeyState(
        for object: Any?,
        seqList: [Any]?,
        config: EncodeConfig,
        depth: Int
    ) -> EncodeKeyState {
        if let seqList {
            switch seqList.count {
            case 0:
                return .none
            case 1:
                return .single(0)
            default:
                return .many(Array(0..<seqList.count))
            }
        }

        switch object {
        case let od as OrderedDictionary<String, Any>:
            switch od.count {
            case 0:
                return .none
            case 1:
                guard let firstKey = od.keys.first else { return .none }
                return .single(firstKey)
            default:
                var result = Array(od.keys)
                if config.sort == nil, depth > 0 {
                    result = partitionPrimitiveKeysFirst(result, sortGroups: config.encoder != nil) { key in
                        isContainer(od[key])
                    }
                }

                if let sort = config.sort {
                    result = result.sorted { first, second in sort(first, second) < 0 }
                }

                return .many(result.map { $0 })
            }

        case let dict as [String: Any]:
            switch dict.count {
            case 0:
                return .none
            case 1:
                guard let firstKey = dict.keys.first else { return .none }
                return .single(firstKey)
            default:
                var result = [String]()
                result.reserveCapacity(dict.count)
                for (key, _) in dict {
                    result.append(key)
                }

                if config.sort == nil, depth > 0, config.encoder != nil {
                    result = partitionPrimitiveKeysFirst(result) { key in
                        isContainer(dict[key])
                    }
                }

                if let sort = config.sort {
                    result = result.sorted { first, second in sort(first, second) < 0 }
                }

                return .many(result.map { $0 })
            }

        case let nd as NSDictionary:
            switch nd.count {
            case 0:
                return .none
            case 1:
                guard let key = nd.allKeys.first else { return .none }
                return .single(key)
            default:
                var result: [Any] = []
                result.reserveCapacity(nd.count)
                nd.forEach { key, _ in result.append(key) }

                if config.sort == nil, depth > 0 {
                    if config.encoder != nil {
                        result = partitionPrimitiveKeysFirst(result) { key in
                            isContainer(nd[key])
                        }
                    } else {
                        result.sort { String(describing: $0) < String(describing: $1) }
                    }
                }

                if let sort = config.sort {
                    result = result.sorted { first, second in sort(first, second) < 0 }
                }

                return keyState(from: result)
            }

        default:
            return .none
        }
    }

    private static func partitionPrimitiveKeysFirst<T>(
        _ keys: [T],
        sortGroups: Bool = true,
        isContainer: (T) -> Bool
    ) -> [T] {
        var primitive: [T] = []
        var containers: [T] = []
        primitive.reserveCapacity(keys.count)

        for key in keys {
            if isContainer(key) {
                containers.append(key)
            } else {
                primitive.append(key)
            }
        }

        if sortGroups {
            primitive.sort { String(describing: $0) < String(describing: $1) }
            containers.sort { String(describing: $0) < String(describing: $1) }
        }

        return primitive + containers
    }

    /// Unwraps an optional value, returning nil if the value is nil or an empty optional.
    @inline(__always)
    private static func unwrapOptional(_ any: Any) -> Any? {
        if let optional = any as? _AnyOptional {
            return optional._wrappedAny
        }
        return any
    }

    /// Describes the value for encoding, handling nil and optional values.
    @inline(__always)
    private static func describe(_ any: Any?, charset: String.Encoding) -> String {
        guard let any = any else { return "" }
        if isOptional(any), unwrapOptional(any) == nil { return "" }
        let materialized = unwrapOptional(any) ?? any
        if let data = materialized as? Data {
            return describeData(data, charset: charset)
        }
        return String(describing: materialized)
    }

    /// Converts a value to an array if it is an array-like type.
    @inline(__always)
    private static func arrayize(_ value: Any?) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let nsArray = value as? NSArray { return nsArray.map { $0 } }
        return nil
    }

    /// Describes a value for comma-separated encoding, handling nil and optional values.
    @inline(__always)
    private static func describeForComma(_ any: Any?, charset: String.Encoding) -> String {
        guard let any = any else { return "" }
        if any is NSNull { return "" }
        if isOptional(any), unwrapOptional(any) == nil { return "" }
        let materialized = unwrapOptional(any) ?? any
        if materialized is NSNull { return "" }
        if let data = materialized as? Data {
            return describeData(data, charset: charset)
        }
        return String(describing: materialized)
    }

    @inline(__always)
    private static func describeData(_ data: Data, charset: String.Encoding) -> String {
        if let decoded = String(bytes: data, encoding: charset) {
            return decoded
        }
        if charset == .utf8 {
            // Preserve permissive UTF-8 fallback by replacing invalid byte sequences.
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: data)
    }

    @inline(__always)
    private static func containerIdentity(_ value: Any?) -> ObjectIdentifier? {
        guard let value else { return nil }
        // Swift value containers bridge through transient Foundation wrappers whose
        // object identity is not stable. Track only class-backed containers.
        guard type(of: value) is AnyClass else { return nil }

        if let list = value as? NSArray {
            return ObjectIdentifier(list)
        }
        if let dict = value as? NSDictionary {
            return ObjectIdentifier(dict)
        }
        return nil
    }

    /// Checks if the value is a container (array, dictionary, etc.).
    @inline(__always)
    private static func isContainer(_ value: Any?) -> Bool {
        if value is [Any] || value is NSArray { return true }
        if value is [String: Any] || value is NSDictionary { return true }
        if value is OrderedDictionary<String, Any> { return true }
        return false
    }

    @inline(__always)
    private static func isOptional(_ value: Any) -> Bool {
        value is _AnyOptional
    }

    @inline(__always)
    private static func iso8601() -> ISO8601DateFormatter {
        let key = "QsSwift.Encoder.iso8601"
        let dict = Thread.current.threadDictionary
        if let formatter = dict[key] as? ISO8601DateFormatter { return formatter }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dict[key] = formatter
        return formatter
    }
}

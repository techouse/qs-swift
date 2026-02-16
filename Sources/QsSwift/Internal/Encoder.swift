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

    /// Encodes the given data into a query string format.
    ///
    /// - Parameters:
    ///   - data: The data to encode; can be any type.
    ///   - undefined: If true, will not encode undefined values.
    ///   - sideChannel: A map table for tracking cyclic references.
    ///   - prefix: An optional prefix for the encoded string.
    ///   - generateArrayPrefix: A generator for array prefixes.
    ///   - commaRoundTrip: If true, uses comma for array encoding.
    ///   - commaCompactNulls: When true, drops `nil` entries before joining comma lists.
    ///   - allowEmptyLists: If true, allows empty lists in the output.
    ///   - strictNullHandling: If true, handles nulls strictly.
    ///   - skipNulls: If true, skips null values in the output.
    ///   - encodeDotInKeys: If true, encodes dots in keys.
    ///   - encoder: An optional custom encoder function.
    ///   - serializeDate: An optional date serializer function.
    ///   - sort: An optional sorter for keys.
    ///   - filter: An optional filter to apply to the data.
    ///   - allowDots: If true, allows dots in keys.
    ///   - format: The format to use for encoding (default is RFC3986).
    ///   - formatter: A custom formatter function.
    ///   - encodeValuesOnly: If true, only encodes values without keys.
    ///   - charset: The character encoding to use (default is UTF-8).
    ///   - addQueryPrefix: If true, adds a '?' prefix to the output.
    ///   - depth: The current depth in the encoding process (used for recursion).
    /// - Returns: The encoded result as Any (typically a String or [String]).
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
        let generator = generateArrayPrefix ?? listFormat.generator
        let isComma = (listFormat == .comma)
        let commaRoundTripEffective = (commaRoundTrip == true)
        let fmt = formatter ?? format.formatter
        let keyPrefix = prefix ?? (addQueryPrefix ? "?" : "")

        if depth >= iterativeFallbackDepth,
            canUseIterativeDeepFallback(
                listFormat: listFormat,
                commaRoundTrip: commaRoundTrip,
                commaCompactNulls: commaCompactNulls,
                allowEmptyLists: allowEmptyLists,
                strictNullHandling: strictNullHandling,
                skipNulls: skipNulls,
                encodeDotInKeys: encodeDotInKeys,
                sort: sort,
                filter: filter,
                allowDots: allowDots,
                encodeValuesOnly: encodeValuesOnly
            )
        {
            return try encodeIterativeDeepFallback(
                data: data,
                undefined: undefined,
                prefix: keyPrefix,
                depth: depth,
                generator: generator,
                encoder: encoder,
                serializeDate: serializeDate,
                formatter: fmt,
                charset: charset
            )
        }

        var obj: Any? = data

        let objWrapper: WeakWrapper? = {
            guard let objRef = data as? AnyObject else { return nil }
            // Optional: narrow to Foundation containers if you like
            if objRef is NSArray || objRef is NSDictionary { return WeakWrapper(objRef) }
            return nil
        }()

        var tmpSc: NSMapTable<AnyObject, AnyObject>? = sideChannel
        var step = 0
        var findFlag = false

        // Walk ancestors to detect cycles
        while !findFlag {
            guard let next = tmpSc?.object(forKey: SENTINEL) as? NSMapTable<AnyObject, AnyObject>
            else { break }
            step += 1

            if let objWrapper = objWrapper, let pos = next.object(forKey: objWrapper) as? NSNumber {
                if pos.intValue == step {
                    throw EncodeError.cyclicObject
                } else {
                    findFlag = true
                }
            }

            if next.object(forKey: SENTINEL) == nil {
                step = 0
            }
            // **advance to the parent for the next iteration**
            tmpSc = next
        }

        // Apply filter transformation FIRST, with safe adoption rules
        if let functionFilter = filter as? FunctionFilter {
            let transformed = functionFilter.function(keyPrefix, obj)
            if isContainer(obj) {
                // for containers, adopt whatever the filter returns
                obj = transformed
            } else {
                // for primitives, only adopt if the filter did not return a container
                if transformed == nil || !isContainer(transformed) {
                    obj = transformed
                }
            }
        }

        // Then do type-specific normalization
        if let date = obj as? Date {
            obj = serializeDate?(date) ?? Self.iso8601().string(from: date)
        } else if isComma, let iterable = obj as? [Any] {
            obj = iterable.map { element -> Any in
                if let date = element as? Date {
                    return serializeDate?(date) ?? Self.iso8601().string(from: date)
                }
                return element
            }
        }

        // Handle undefined and null cases
        if !undefined && obj == nil {
            if strictNullHandling {
                if let encoder = encoder, !encodeValuesOnly {
                    return encoder(prefix, charset, format)
                }
                return keyPrefix
            }
            obj = ""
        }

        if skipNulls, obj is NSNull {
            // Drop direct null payloads entirely when skipNulls is enabled.
            return []
        }

        // Special-case NSNull to match original qs.js behavior
        if obj is NSNull {
            if strictNullHandling {
                // key only; encode key if an encoder is provided, otherwise leave it raw
                if let enc = encoder, !encodeValuesOnly {
                    return fmt.apply(enc(keyPrefix, nil, nil))
                } else {
                    return fmt.apply(keyPrefix)
                }
            } else {
                // key with empty value
                if let enc = encoder {
                    let keyPart = encodeValuesOnly ? keyPrefix : enc(keyPrefix, nil, nil)
                    let valPart = enc("", nil, nil)  // empty string
                    return "\(fmt.apply(keyPart))=\(fmt.apply(valPart))"
                } else {
                    // no encoder -> no percent-encoding for the key
                    return "\(fmt.apply(keyPrefix))="
                }
            }
        }

        // ---- Normalize the scalar once (unwrap Optional, collapse Optional.none to nil) ----
        let normalizedScalar: Any? = {
            guard let some = obj else { return nil }
            return unwrapOptional(some) ?? some
        }()

        // Handle primitives
        if Utils.isNonNullishPrimitive(normalizedScalar, skipNulls: skipNulls)
            || normalizedScalar is Data
        {
            if let enc = encoder {
                let keyPart = encodeValuesOnly ? keyPrefix : enc(keyPrefix, nil, nil)
                let valPart = enc(normalizedScalar, nil, nil)  // pass unwrapped
                return "\(fmt.apply(keyPart))=\(fmt.apply(valPart))"
            }
            return "\(fmt.apply(keyPrefix))=\(fmt.apply(describe(normalizedScalar, charset: charset)))"  // unwrapped
        }

        var values: [Any] = []

        if undefined { return values }

        var arrayView = arrayize(obj)

        // Determine object keys
        let objKeys: [Any] = {
            if isComma, let elems0 = arrayView {
                var elems = elems0

                if commaCompactNulls {
                    elems = elems.compactMap { element -> Any? in
                        if element is NSNull { return nil }
                        if isOptional(element) {
                            guard let unwrapped = unwrapOptional(element) else { return nil }
                            if unwrapped is NSNull { return nil }
                            return unwrapped
                        }
                        return element
                    }
                    arrayView = elems
                    obj = elems
                }

                if encodeValuesOnly, let encoder = encoder {
                    elems = elems.map { el in
                        encoder(describeForComma(el, charset: charset), nil, nil)
                    }
                    obj = elems
                }
                arrayView = arrayize(obj)

                if !elems.isEmpty {
                    let joined = elems.map { describeForComma($0, charset: charset) }.joined(
                        separator: ",")
                    // if strictNullHandling and joined is empty, use NSNull() to mean “no value”
                    let valueForJoin: Any =
                        joined.isEmpty
                        ? (strictNullHandling ? NSNull() : "")
                        : joined
                    return [["value": valueForJoin] as [String: Any]]
                }

                return [["value": Undefined.instance] as [String: Any]]
            } else if let iterableFilter = filter as? IterableFilter {
                return iterableFilter.iterable
            } else {
                let keys: [Any] = {
                    switch obj {
                    case let od as OrderedDictionary<String, Any>:
                        var _keys = [String]()
                        _keys.reserveCapacity(od.count)
                        for (_key, _) in od { _keys.append(_key) }  // preserves insertion order
                        if let sort = sort {
                            _keys = _keys.sorted { sort($0, $1) < 0 }
                        } else if depth > 0 {
                            let split = _keys.stablePartition { key in isContainer(od[key]) }
                            if encoder != nil {
                                _keys[..<split].sort()
                                _keys[split...].sort()
                            }
                        }
                        return _keys

                    case let dict as [String: Any]:
                        // enumerate to preserve insertion order
                        var _keys = [String]()
                        _keys.reserveCapacity(dict.count)
                        for (_key, _) in dict { _keys.append(_key) }
                        if let sort = sort {
                            _keys = _keys.sorted { sort($0, $1) < 0 }
                            return _keys
                        }
                        // At nested depths, partition: primitives first, containers later (stable)
                        if depth > 0, encoder != nil {
                            let split = _keys.stablePartition { key in isContainer(dict[key]) }  // containers last
                            _keys[..<split].sort()  // primitives A..Z
                            _keys[split...].sort()  // containers A..Z
                        }
                        return _keys

                    case let nd as NSDictionary:
                        var ks: [Any] = []
                        ks.reserveCapacity(nd.count)
                        nd.forEach { key, _ in ks.append(key) }

                        if let sort = sort {
                            ks = ks.sorted { sort($0, $1) < 0 }
                        } else if depth > 0 {
                            if encoder != nil {
                                // Partition: primitives first, containers later (stable), like Swift dict.
                                var prim: [Any] = []
                                var cont: [Any] = []
                                prim.reserveCapacity(ks.count)
                                cont.reserveCapacity(ks.count)
                                for key in ks {
                                    let value = nd[key]
                                    if isContainer(value) {
                                        cont.append(key)
                                    } else {
                                        prim.append(key)
                                    }
                                }
                                prim.sort { String(describing: $0) < String(describing: $1) }
                                cont.sort { String(describing: $0) < String(describing: $1) }
                                ks = prim + cont
                            } else {
                                // No custom encoder → match the “feel” of Swift dict literals:
                                // sort lexicographically so "" comes before "a"
                                ks.sort { String(describing: $0) < String(describing: $1) }
                            }
                        }
                        return ks

                    case _ where arrayView != nil:
                        if let arr = arrayView {
                            return Array(0..<arr.count)
                        }
                        return []

                    default:
                        return []
                    }
                }()

                if let sort = sort { return keys.sorted { sort($0, $1) < 0 } }
                return keys
            }
        }()

        let encodedPrefix =
            encodeDotInKeys
            ? keyPrefix.replacingOccurrences(of: ".", with: "%2E")
            : keyPrefix

        let adjustedPrefix: String = {
            if isComma, commaRoundTrip, let arr = arrayView, arr.count == 1 {
                return "\(encodedPrefix)[]"
            }
            return encodedPrefix
        }()

        if allowEmptyLists, let arr = arrayView, arr.isEmpty {
            return "\(adjustedPrefix)[]"
        }

        // Process each key
        for index in 0..<objKeys.count {
            let key = objKeys[index]

            let (value, valueUndefined): (Any?, Bool) = {
                if let keyDict = key as? [String: Any], let _value = keyDict["value"] {
                    return (_value is Undefined ? nil : _value, _value is Undefined)
                } else {
                    switch obj {

                    case let od as OrderedDictionary<String, Any>:
                        if let keyString = key as? String {
                            let value = od[keyString]
                            let contains = od.index(forKey: keyString) != nil
                            return (value, value == nil && !contains)
                        }
                        return (nil, true)

                    case let dict as [String: Any]:
                        if let keyString = key as? String {
                            let value = dict[keyString].flatMap { unwrapOptional($0) } ?? dict[keyString]
                            return (value, value == nil && !dict.keys.contains(keyString))
                        }
                        return (nil, true)

                    case let nd as NSDictionary:
                        let value = nd[key]
                        // NSDictionary can’t store nil; nil here means “absent”
                        return (value, value == nil)

                    default:
                        if let arr = arrayView, let idx = key as? Int, idx >= 0, idx < arr.count {
                            return (arr[idx], false)
                        }
                        return (nil, true)
                    }
                }
            }()

            if skipNulls && (value == nil || value is NSNull) {
                continue
            }

            let rawKey = String(describing: key)
            let encodedKey: String = {
                if allowDots && encodeDotInKeys {
                    return rawKey.replacingOccurrences(of: ".", with: "%2E")
                } else {
                    return rawKey
                }
            }()

            let keyPrefix: String = {
                if arrayView != nil {
                    return generator(adjustedPrefix, encodedKey)
                }
                return allowDots
                    ? "\(encodedPrefix).\(encodedKey)"
                    : "\(encodedPrefix)[\(encodedKey)]"
            }()

            // Record the current container for cycle detection
            if let objWrapper = objWrapper, isContainer(obj) {
                sideChannel.setObject(NSNumber(value: step), forKey: objWrapper)
            }

            // Create child side-channel and link to parent
            // Link child → parent so ancestor walk can detect cycles via SENTINEL chain.
            let valueSideChannel = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()
            valueSideChannel.setObject(sideChannel, forKey: SENTINEL)

            let encoded: Any = try encode(
                data: value,
                undefined: valueUndefined,
                sideChannel: valueSideChannel,
                prefix: keyPrefix,
                generateArrayPrefix: generator,
                listFormat: listFormat,
                commaRoundTrip: commaRoundTripEffective,
                commaCompactNulls: commaCompactNulls,
                allowEmptyLists: allowEmptyLists,
                strictNullHandling: strictNullHandling,
                skipNulls: skipNulls,
                encodeDotInKeys: encodeDotInKeys,
                encoder: (isComma && encodeValuesOnly && obj is [Any]) ? nil : encoder,
                serializeDate: serializeDate,
                sort: sort,
                filter: filter,
                allowDots: allowDots,
                format: format,
                formatter: fmt,
                encodeValuesOnly: encodeValuesOnly,
                charset: charset,
                addQueryPrefix: addQueryPrefix,
                depth: depth + 1
            )

            if let encodedArray = encoded as? [Any] {
                values.append(contentsOf: encodedArray)
            } else {
                values.append(encoded)
            }
        }

        return values
    }
}

extension QsSwift.Encoder {
    // MARK: - Helpers

    /// Use a dedicated class marked @unchecked Sendable to satisfy concurrency checks.
    private final class Sentinel: NSObject, @unchecked Sendable {}

    /// Top-level unique token for cycle detection
    private static let SENTINEL = Sentinel()
    private static let iterativeFallbackDepth = 256

    // swiftlint:disable:next function_parameter_count
    private static func canUseIterativeDeepFallback(
        listFormat: ListFormat,
        commaRoundTrip: Bool,
        commaCompactNulls: Bool,
        allowEmptyLists: Bool,
        strictNullHandling: Bool,
        skipNulls: Bool,
        encodeDotInKeys: Bool,
        sort: Sorter?,
        filter: Filter?,
        allowDots: Bool,
        encodeValuesOnly: Bool
    ) -> Bool {
        listFormat == .indices
            && !commaRoundTrip
            && !commaCompactNulls
            && !allowEmptyLists
            && !strictNullHandling
            && !skipNulls
            && !encodeDotInKeys
            && sort == nil
            && filter == nil
            && !allowDots
            && !encodeValuesOnly
    }

    private struct IterativeNode {
        let value: Any?
        let undefined: Bool
        let prefix: String
        let depth: Int
    }

    private enum IterativeTask {
        case visit(IterativeNode)
        case leaveContainer(ObjectIdentifier)
    }

    // swiftlint:disable:next function_parameter_count
    private static func encodeIterativeDeepFallback(
        data: Any?,
        undefined: Bool,
        prefix: String,
        depth: Int,
        generator: ListFormatGenerator,
        encoder: ValueEncoder?,
        serializeDate: DateSerializer?,
        formatter: Formatter,
        charset: String.Encoding
    ) throws -> Any {
        if undefined { return [Any]() }

        var stack: [IterativeTask] = [
            .visit(.init(value: data, undefined: undefined, prefix: prefix, depth: depth))
        ]
        var values: [Any] = []
        values.reserveCapacity(32)
        var activeContainers: Set<ObjectIdentifier> = []

        while let task = stack.popLast() {
            if case .leaveContainer(let containerID) = task {
                activeContainers.remove(containerID)
                continue
            }

            guard case .visit(let node) = task else { continue }

            var current = node.value

            if let date = current as? Date {
                current = serializeDate?(date) ?? iso8601().string(from: date)
            }

            if !node.undefined && current == nil {
                current = ""
            }

            if let containerID = containerIdentity(current) {
                if activeContainers.contains(containerID) {
                    throw EncodeError.cyclicObject
                }
                activeContainers.insert(containerID)
                stack.append(.leaveContainer(containerID))
            }

            if current is NSNull {
                if let enc = encoder {
                    let keyPart = enc(node.prefix, nil, nil)
                    let valPart = enc("", nil, nil)
                    values.append("\(formatter.apply(keyPart))=\(formatter.apply(valPart))")
                } else {
                    values.append("\(formatter.apply(node.prefix))=")
                }
                continue
            }

            let normalizedScalar: Any? = {
                guard let some = current else { return nil }
                return unwrapOptional(some) ?? some
            }()

            if Utils.isNonNullishPrimitive(normalizedScalar) || normalizedScalar is Data {
                if let enc = encoder {
                    let keyPart = enc(node.prefix, nil, nil)
                    let valPart = enc(normalizedScalar, nil, nil)
                    values.append("\(formatter.apply(keyPart))=\(formatter.apply(valPart))")
                } else {
                    values.append(
                        "\(formatter.apply(node.prefix))=\(formatter.apply(describe(normalizedScalar, charset: charset)))"
                    )
                }
                continue
            }

            if let arr = arrayize(current) {
                if arr.isEmpty { continue }
                for idx in stride(from: arr.count - 1, through: 0, by: -1) {
                    let childPrefix = generator(node.prefix, String(idx))
                    stack.append(
                        .visit(
                            .init(
                                value: arr[idx],
                                undefined: false,
                                prefix: childPrefix,
                                depth: node.depth + 1
                            )))
                }
                continue
            }

            let entries = orderedEntriesForIterativeFallback(
                current: current,
                depth: node.depth,
                hasEncoder: (encoder != nil)
            )

            for (key, child) in entries.reversed() {
                let childPrefix = "\(node.prefix)[\(key)]"
                stack.append(
                    .visit(
                        .init(
                            value: child,
                            undefined: false,
                            prefix: childPrefix,
                            depth: node.depth + 1
                        )))
            }
        }

        return values
    }

    @inline(__always)
    private static func containerIdentity(_ value: Any?) -> ObjectIdentifier? {
        guard let value else { return nil }

        // Only track real class-backed containers. Swift value containers can bridge to
        // transient Foundation wrappers whose object identity is not stable.
        guard type(of: value) is AnyClass else { return nil }

        if let array = value as? NSArray {
            return ObjectIdentifier(array)
        }
        if let dictionary = value as? NSDictionary {
            return ObjectIdentifier(dictionary)
        }
        return nil
    }

    private static func orderedEntriesForIterativeFallback(
        current: Any?,
        depth: Int,
        hasEncoder: Bool
    ) -> [(String, Any)] {
        switch current {
        case let od as OrderedDictionary<String, Any>:
            var keys = Array(od.keys)
            if depth > 0 {
                let split = keys.stablePartition { key in isContainer(od[key]) }
                if hasEncoder {
                    keys[..<split].sort()
                    keys[split...].sort()
                }
            }
            return keys.compactMap { key in od[key].map { (key, $0) } }

        case let dict as [String: Any]:
            var keys = [String]()
            keys.reserveCapacity(dict.count)
            for (key, _) in dict { keys.append(key) }
            if depth > 0, hasEncoder {
                let split = keys.stablePartition { key in isContainer(dict[key]) }
                keys[..<split].sort()
                keys[split...].sort()
            }
            return keys.compactMap { key in dict[key].map { (key, $0) } }

        case let nd as NSDictionary:
            var keys: [Any] = []
            keys.reserveCapacity(nd.count)
            nd.forEach { key, _ in keys.append(key) }

            if depth > 0 {
                if hasEncoder {
                    var prim: [Any] = []
                    var cont: [Any] = []
                    prim.reserveCapacity(keys.count)
                    cont.reserveCapacity(keys.count)
                    for key in keys {
                        let value = nd[key]
                        if isContainer(value) {
                            cont.append(key)
                        } else {
                            prim.append(key)
                        }
                    }
                    prim.sort { String(describing: $0) < String(describing: $1) }
                    cont.sort { String(describing: $0) < String(describing: $1) }
                    keys = prim + cont
                } else {
                    keys.sort { String(describing: $0) < String(describing: $1) }
                }
            }

            var out: [(String, Any)] = []
            out.reserveCapacity(keys.count)
            for key in keys {
                if let value = nd[key] {
                    out.append((String(describing: key), value))
                }
            }
            return out

        default:
            return []
        }
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
        if isOptional(any), unwrapOptional(any) == nil { return "" }  // Optional.none
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
        if isOptional(any), unwrapOptional(any) == nil { return "" }  // Optional.none
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
            // Keep payload visible for malformed UTF-8 instead of collapsing to empty.
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: data)
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

// swiftlint:disable file_length
import Foundation
import OrderedCollections

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

        if skipNulls, obj is NSNull {
            // drop this key entirely
            return []  // signal "no pairs produced"
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
            return "\(fmt.apply(keyPrefix))=\(fmt.apply(describe(normalizedScalar)))"  // unwrapped
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
                    elems = elems.map { el in encoder(describeForComma(el), nil, nil) }
                    obj = elems
                }
                arrayView = arrayize(obj)

                if !elems.isEmpty {
                    let joined = elems.map { describeForComma($0) }.joined(separator: ",")
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

    /// Unwraps an optional value, returning nil if the value is nil or an empty optional.
    @inline(__always)
    private static func unwrapOptional(_ any: Any) -> Any? {
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle != .optional { return any }
        return mirror.children.first?.value
    }

    /// Describes the value for encoding, handling nil and optional values.
    @inline(__always)
    private static func describe(_ any: Any?) -> String {
        guard let any = any else { return "" }
        if let unwrapped = unwrapOptional(any) {
            return String(describing: unwrapped)
        }
        return ""  // Optional.none
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
    private static func describeForComma(_ any: Any?) -> String {
        guard let any = any else { return "" }
        if any is NSNull { return "" }
        if let unwrapped = unwrapOptional(any) {
            if unwrapped is NSNull { return "" }
            return String(describing: unwrapped)
        }
        return ""
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
        Mirror(reflecting: value).displayStyle == .optional
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

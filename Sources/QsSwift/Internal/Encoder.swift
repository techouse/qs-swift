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
    static func encode(
        data: Any?,
        undefined: Bool,
        sideChannel: NSMapTable<AnyObject, AnyObject>,
        prefix: String? = nil,
        generateArrayPrefix: ListFormatGenerator? = nil,
        listFormat: ListFormat = .indices,
        commaRoundTrip: Bool = false,
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
            if let objRef = data as? AnyObject {
                return WeakWrapper(objRef)
            }
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
            obj = serializeDate?(date) ?? ISO8601DateFormatter().string(from: date)
        } else if isComma, let iterable = obj as? [Any] {
            obj = iterable.map { v -> Any in
                if let d = v as? Date {
                    return serializeDate?(d) ?? ISO8601DateFormatter().string(from: d)
                }
                return v
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

        // Handle primitives
        if Utils.isNonNullishPrimitive(obj, skipNulls: skipNulls) || obj is Data {
            if let enc = encoder {
                let keyPart = encodeValuesOnly ? keyPrefix : enc(keyPrefix, nil, nil)
                let valPart = enc(obj, nil, nil)
                return "\(fmt.apply(keyPart))=\(fmt.apply(valPart))"
            }
            return "\(fmt.apply(keyPrefix))=\(fmt.apply(describe(obj)))"
        }

        var values: [Any] = []

        if undefined { return values }

        // Determine object keys
        let objKeys: [Any] = {
            if isComma, let elems0 = arrayize(obj) {
                var elems = elems0
                if encodeValuesOnly, let encoder = encoder {
                    elems = elems0.map { el in encoder(describeForComma(el), nil, nil) }
                    obj = elems
                }

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
                        var k = [String]()
                        k.reserveCapacity(od.count)
                        for (kk, _) in od { k.append(kk) }  // preserves insertion order
                        if let sort = sort {
                            k = k.sorted { sort($0, $1) < 0 }
                        } else if depth > 0 {
                            let split = k.stablePartition { key in isContainer(od[key]) }
                            if encoder != nil {
                                k[..<split].sort()
                                k[split...].sort()
                            }
                        }
                        return k

                    case let od as OrderedDictionary<AnyHashable, Any>:
                        var k = [AnyHashable]()
                        k.reserveCapacity(od.count)
                        for (kk, _) in od { k.append(kk) }
                        if let sort = sort {
                            k = k.sorted { sort($0, $1) < 0 }
                        } else if depth > 0 {
                            let split = k.stablePartition { key in isContainer(od[key]) }
                            if encoder != nil {
                                k[..<split].sort { String(describing: $0) < String(describing: $1) }
                                k[split...].sort { String(describing: $0) < String(describing: $1) }
                            }
                        }
                        return k

                    case let dict as [String: Any]:
                        // enumerate to preserve insertion order
                        var k = [String]()
                        k.reserveCapacity(dict.count)
                        for (kk, _) in dict { k.append(kk) }
                        if let sort = sort {
                            k = k.sorted { sort($0, $1) < 0 }
                            return k
                        }
                        // At nested depths, partition: primitives first, containers later (stable)
                        if depth > 0, encoder != nil {
                            let split = k.stablePartition { key in isContainer(dict[key]) }  // containers last
                            k[..<split].sort()  // primitives A..Z
                            k[split...].sort()  // containers A..Z
                        }
                        return k

                    case let dict as [AnyHashable: Any]:
                        var k = [AnyHashable]()
                        k.reserveCapacity(dict.count)
                        for (kk, _) in dict { k.append(kk) }
                        if let sort = sort {
                            k = k.sorted { sort($0, $1) < 0 }
                            return k
                        }
                        if depth > 0, encoder != nil {
                            let split = k.stablePartition { key in isContainer(dict[key]) }
                            k[..<split].sort { String(describing: $0) < String(describing: $1) }
                            k[split...].sort { String(describing: $0) < String(describing: $1) }
                        }
                        return k

                    case _ where arrayize(obj) != nil:
                        let count = arrayize(obj)!.count
                        return Array(0..<count)

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
            if isComma, commaRoundTrip, let arr = arrayize(obj), arr.count == 1 {
                return "\(encodedPrefix)[]"
            }
            return encodedPrefix
        }()

        if allowEmptyLists, let arr = arrayize(obj), arr.isEmpty {
            return "\(adjustedPrefix)[]"
        }

        // Process each key
        for i in 0..<objKeys.count {
            let key = objKeys[i]

            let (value, valueUndefined): (Any?, Bool) = {
                if let keyDict = key as? [String: Any], let v = keyDict["value"] {
                    return (v is Undefined ? nil : v, v is Undefined)
                } else {
                    switch obj {

                    case let od as OrderedDictionary<String, Any>:
                        if let k = key as? String {
                            let v = od[k]
                            let contains = od.index(forKey: k) != nil
                            return (v, v == nil && !contains)
                        }
                        return (nil, true)

                    case let od as OrderedDictionary<AnyHashable, Any>:
                        if let k = key as? AnyHashable {
                            let v = od[k]
                            let contains = od.index(forKey: k) != nil
                            return (v, v == nil && !contains)
                        }
                        return (nil, true)

                    case let dict as [String: Any]:
                        if let k = key as? String {
                            let v = dict[k]
                            return (v, v == nil && !dict.keys.contains(k))
                        }
                        return (nil, true)

                    case let dict as [AnyHashable: Any]:
                        if let k = key as? AnyHashable {
                            let v = dict[k]
                            return (v, v == nil && !dict.keys.contains(k))
                        }
                        return (nil, true)

                    default:
                        if let arr = arrayize(obj), let idx = key as? Int, idx >= 0, idx < arr.count
                        {
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
                if arrayize(obj) != nil {
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

    // MARK: - Helpers

    /// Use a dedicated class marked @unchecked Sendable to satisfy concurrency checks.
    private final class Sentinel: NSObject, @unchecked Sendable {}

    /// Top-level unique token for cycle detection
    private static let SENTINEL = Sentinel()

    /// Unwraps an optional value, returning nil if the value is nil or an empty optional.
    @inline(__always)
    private static func unwrapOptional(_ any: Any) -> Any? {
        let m = Mirror(reflecting: any)
        if m.displayStyle != .optional { return any }
        return m.children.first?.value
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
    private static func arrayize(_ v: Any?) -> [Any]? {
        if let a = v as? [Any] { return a }
        if let ns = v as? NSArray { return ns.map { $0 } }  // handles [String], [Int], etc.
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
    private static func isContainer(_ v: Any?) -> Bool {
        if v is [Any] || v is NSArray { return true }
        if v is [String: Any] || v is [AnyHashable: Any] || v is NSDictionary { return true }
        if v is OrderedDictionary<String, Any> || v is OrderedDictionary<AnyHashable, Any> {
            return true
        }
        return false
    }
}

import Algorithms
import Foundation
import OrderedCollections

extension Qs {
    /// Encode a Dictionary- or Array-like value into a query string.
    ///
    /// Accepts:
    /// - `[String: Any]` or `OrderedDictionary<String, Any>`
    /// - `[Any]` (becomes `["0": v0, "1": v1, ...]`)
    ///
    /// Behavior highlights:
    /// - **Nulls / undefined**:
    ///   - When `skipNulls == true`, both missing and `NSNull()` entries are skipped.
    ///   - Otherwise, absent values are treated as `""` if `strictNullHandling == false`,
    ///     and as `nil` (no `=`) if `strictNullHandling == true`.
    /// - **Dates** use `options.getDateSerializer` (ISO 8601 by default).
    /// - **Lists** follow `listFormat` (`.indices`, `.brackets`, `.repeatKey`, `.comma`),
    ///   with optional `commaRoundTrip` behavior for single-item comma lists.
    /// - **Dots** in keys can be left as-is, allowed as path separators (`allowDots`),
    ///   or percent-encoded with `encodeDotInKeys`.
    /// - **Charset sentinel** (Rails-style `utf8=✓`) is optionally prefixed.
    ///
    /// Ordering rules:
    /// - If `options.sort != nil`, that sorter decides order everywhere.
    /// - If `options.sort == nil` **and** `options.encode == false`, key order follows the input
    ///   container’s traversal order (e.g., `OrderedDictionary` preserves insertion order).
    /// - If `options.sort == nil` **and** `options.encode == true`, a deterministic default is applied
    ///   at the top level: non-empty keys sorted A→Z with empty keys (`""`) moved to the end.
    /// - Arrays preserve input order in all list formats.
    ///
    /// - Parameters:
    ///   - data: The value to encode. `nil` yields `""`.
    ///   - options: Encoder settings. See `EncodeOptions`.
    /// - Returns: The encoded query string (no leading `?` unless `addQueryPrefix` is set).
    ///
    /// - Throws: If a cycle is detected in the object graph (e.g. a collection that refers to itself).
    ///
    /// - Tip: For fully deterministic output across platforms, either pass an explicit `sort`
    ///   or supply an `OrderedDictionary` as input.
    public static func encode(
        _ data: Any?,
        options: EncodeOptions = EncodeOptions()
    ) throws -> String {
        guard let data = data else { return "" }

        var obj: [String: Any] = [:]
        var objKeys: [Any]?
        var arrayIndexKeys: [Any]?
        var keysLockedByFilter = false  // set when IterableFilter provides explicit order

        // Normalize the top-level container to [String: Any] and capture a stable key order.
        if let map = data as? [String: Any] {
            // Preserve caller traversal order by building an ordered view.
            let od = OrderedDictionary(uniqueKeysWithValues: map.map { ($0.key, $0.value) })
            obj = map
            objKeys = Array(od.keys)

        } else if let od = data as? OrderedDictionary<String, Any> {
            obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
            objKeys = Array(od.keys)  // preserves insertion order

        } else if let odNS = data as? OrderedDictionary<NSString, Any> {
            // Preserve insertion order, normalize keys to Swift String
            var od = OrderedDictionary<String, Any>()
            od.reserveCapacity(odNS.count)
            for (key, value) in odNS { od[String(key)] = value }
            obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
            objKeys = Array(od.keys)

        } else if let odAH = data as? OrderedDictionary<AnyHashable, Any> {
            // Preserve insertion order, normalize heterogeneous keys
            var od = OrderedDictionary<String, Any>()
            od.reserveCapacity(odAH.count)
            for (key, value) in odAH { od[String(describing: key)] = value }
            obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
            objKeys = Array(od.keys)

        } else if let dictAH = data as? [AnyHashable: Any] {
            // Plain dictionary with non-String keys → stringified keys; order = hash map traversal
            var od = OrderedDictionary<String, Any>()
            od.reserveCapacity(dictAH.count)
            for (key, value) in dictAH { od[String(describing: key)] = value }
            obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
            objKeys = Array(od.keys)

        } else if let nd = data as? NSDictionary {
            // Bridge NSDictionary; enumeration order is not guaranteed/deterministic
            var od = OrderedDictionary<String, Any>()
            od.reserveCapacity(nd.count)
            nd.forEach { key, value in od[String(describing: key)] = value }
            obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
            objKeys = Array(od.keys)

        } else if let arr = data as? [Any] {
            // Promote array → object with string indices.
            var od = OrderedDictionary<String, Any>()
            for (index, element) in arr.enumerated() { od[String(index)] = element }
            obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
            arrayIndexKeys = Array(od.keys)

        } else {
            // Unsupported top-level type → empty output (matches other ports’ behavior).
            return ""
        }

        if obj.isEmpty { return "" }

        // Root-level filters:
        // - IterableFilter provides an explicit key order (authoritative).
        // - FunctionFilter allows transforming the root object, but only adopt it if the result is container-shaped (map or array).
        if let functionFilter = options.filter as? FunctionFilter {
            let filtered = functionFilter.function("", obj)

            // Adopt container results only; primitives are ignored at the root.
            if let map = filtered as? [String: Any] {
                obj = map
                objKeys = Array(
                    OrderedDictionary(uniqueKeysWithValues: map.map { ($0.key, $0.value) }).keys)
            } else if let mapAnyHashable = filtered as? [AnyHashable: Any] {
                var out: [String: Any] = [:]
                out.reserveCapacity(mapAnyHashable.count)
                for (key, value) in mapAnyHashable { out[String(describing: key)] = value }
                obj = out
                objKeys = Array(
                    OrderedDictionary(uniqueKeysWithValues: out.map { ($0.key, $0.value) }).keys)
            } else if let ordered = filtered as? OrderedDictionary<String, Any> {
                obj = Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, $0.value) })
                objKeys = Array(ordered.keys)
            } else if let nd = filtered as? NSDictionary {
                var out: [String: Any] = [:]
                nd.forEach { key, value in out[String(describing: key)] = value }
                obj = out
                objKeys = Array(out.keys)
            } else if let array = filtered as? [Any] {
                var od = OrderedDictionary<String, Any>()
                for (index, element) in array.enumerated() { od[String(index)] = element }
                obj = Dictionary(uniqueKeysWithValues: od.map { ($0.key, $0.value) })
                objKeys = Array(od.keys)
            }
        }

        if let it = options.filter as? IterableFilter {
            objKeys = it.iterable
            keysLockedByFilter = true
        }

        // If no custom key list from filter, use the map keys (or array indices).
        if objKeys == nil {
            objKeys = arrayIndexKeys ?? Array(obj.keys)  // fallback
        }

        // --------- Ordering policy (see doc above) ---------
        if let sorter = options.sort, let keys = objKeys {
            objKeys = keys.sorted { sorter($0, $1) < 0 }
        } else if arrayIndexKeys == nil && options.encode && !keysLockedByFilter, let keys = objKeys {
            // Deterministic default only when percent-encoding is on and filter did not lock keys.
            var ks = keys.compactMap { $0 as? String }  // top-level keys are Strings
            let split = ks.stablePartition { $0.isEmpty }  // empties → back, **stable**
            ks[..<split].sort()  // sort non-empty keys lexically
            objKeys = ks
        }
        // else: preserve traversal order (or filter’s order) as-is

        // Weak side-channel for cycle detection inside the recursive encoder.
        let sideChannel = NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()

        // Build key=value parts
        var parts: [Any] = []
        parts.reserveCapacity(objKeys?.count ?? 0)

        if let keys = objKeys {
            for anyKey in keys {
                guard let key = anyKey as? String else { continue }

                let containsKey = obj.keys.contains(key)
                let value = obj[key]  // may be nil if absent

                // Optionally skip nulls
                if options.skipNulls {
                    // Treat both missing and explicit null (NSNull) as "skip"
                    if value == nil { continue }
                    if value is NSNull { continue }
                }

                // Bridge the encoder/date-serializer configs; avoid capturing `options` repeatedly.
                let valueEncoder: ValueEncoder? = options.encode
                    ? { @Sendable (value: Any?, charset: String.Encoding?, format: Format?) -> String in
                        options.getEncoder(value, charset: charset, format: format)
                    }
                    : nil

                let dateSerializer: DateSerializer = { @Sendable (date: Date) -> String in
                    options.getDateSerializer(date)
                }

                // Delegate to the lower-level encoder for nested traversal & formatting.
                let encoded = try QsSwift.Encoder.encode(
                    data: value,
                    undefined: !containsKey,
                    sideChannel: sideChannel,
                    prefix: key,
                    generateArrayPrefix: options.getListFormat.generator,
                    listFormat: options.getListFormat,
                    commaRoundTrip: (options.getListFormat == .comma)
                        && (options.commaRoundTrip == true),
                    commaCompactNulls: (options.getListFormat == .comma)
                        && options.commaCompactNulls,
                    allowEmptyLists: options.allowEmptyLists,
                    strictNullHandling: options.strictNullHandling,
                    skipNulls: options.skipNulls,
                    encodeDotInKeys: options.encodeDotInKeys,
                    encoder: valueEncoder,
                    serializeDate: dateSerializer,
                    sort: options.sort,
                    filter: options.filter,
                    allowDots: options.getAllowDots,
                    format: options.format,
                    formatter: options.formatter,
                    encodeValuesOnly: options.encodeValuesOnly,
                    charset: options.charset,
                    addQueryPrefix: options.addQueryPrefix,
                    depth: 1
                )

                if let array = encoded as? [Any] {
                    parts.append(contentsOf: array)
                } else {
                    parts.append(encoded)
                }
            }
        }

        // Join with the chosen delimiter
        let joined = parts.lazy.map { String(describing: $0) }.joined(separator: options.delimiter)

        // Build final string with optional '?' and charset sentinel
        var out = ""
        if options.addQueryPrefix { out.append("?") }

        if options.charsetSentinel {
            switch options.charset {
            case .isoLatin1:
                // encodeURIComponent('&#10003;') ("numeric entity" of checkmark)
                out.append(Sentinel.isoString)
                out.append("&")
            case .utf8:
                // encodeURIComponent('✓')
                out.append(Sentinel.charsetString)
                out.append("&")
            default:
                break
            }
        }

        if !joined.isEmpty {
            out.append(joined)
        }

        return out
    }
}

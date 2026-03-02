#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import OrderedCollections
    import QsSwift

    /// Objective-C ⇆ Swift shim for the Qs core.
    ///
    /// Goals:
    /// - **Decode**: accept common Obj-C shapes (`NSString`, `NSDictionary`, `NSArray`) and
    ///   hand the Swift core something it understands with *minimal* transformation.
    /// - **Encode**: accept common Obj-C shapes and materialize **ordered Swift containers**
    ///   (`OrderedDictionary<String, Any>` / `[Any]`) while preserving **object identity**
    ///   (so cycles can be detected by the core and reported as `.cyclicObject`).
    /// - **Undefined bridging**: convert `UndefinedObjC` → `QsSwift.Undefined` without
    ///   disturbing container order or breaking identity cycles.
    ///
    /// Notes on order:
    /// - `NSDictionary` does **not** guarantee enumeration order. Whenever callers
    ///   pass a Swift `OrderedDictionary` or a Swift `[String: Any]`, we preserve
    ///   that insertion order. When callers pass an `NSDictionary`, we emit an
    ///   `OrderedDictionary` in the *enumeration* order we see (best effort),
    ///   but this should not be relied upon for determinism across processes.
    @objc(Qs)
    @objcMembers
    public final class QsBridge: NSObject {

        // MARK: - Decode

        /// Bridge Obj-C input to something `Qs.decode` accepts, then decode.
        ///
        /// - Parameters:
        ///   - input: `NSString` / `String` / `NSDictionary` / `NSArray` / scalars.
        ///   - options: Optional Obj-C decode options.
        ///   - outError: Filled on failure with a Cocoa `NSError`.
        /// - Returns: An `NSDictionary` tree (Swift dictionaries/arrays under the hood).
        public static func decode(
            _ input: Any?,
            options: DecodeOptionsObjC? = nil,
            error outError: NSErrorPointer = nil
        ) -> NSDictionary? {
            do {
                let bridged = bridgeInputForDecode(input)
                let result = try Qs.decode(
                    bridged, options: options?.swift ?? QsSwift.DecodeOptions())
                return result as NSDictionary
            } catch {
                outError?.pointee = error as NSError
                return nil
            }
        }

        // MARK: - Encode

        /// Bridge Obj-C containers to ordered Swift containers, translate `Undefined`,
        /// and then call `Qs.encode`.
        ///
        /// - Parameters:
        ///   - object: `NSString` / `NSDictionary` / `NSArray` / Swift containers / scalars.
        ///   - options: Optional Obj-C encode options.
        ///   - outError: Filled on failure with a Cocoa `NSError`.
        /// - Returns: Encoded query string on success, `nil` and `outError` on failure.
        public static func encode(
            _ object: Any, options: EncodeOptionsObjC? = nil, error outError: NSErrorPointer = nil
        ) -> NSString? {
            do {
                let swiftOptions = options?.swift ?? QsSwift.EncodeOptions()

                if let dictionary = object as? NSDictionary {
                    if _isNarrowObjCEncodeFastPathConfig(options),
                        _isSingleKeyNSDictionaryScalarChainEligible(dictionary)
                    {
                        let str = try Qs.encode(dictionary, options: swiftOptions)
                        return str as NSString
                    }

                    if _isSortedDirectEncodeConfigEligible(options),
                        _isSortedNSStringFoundationGraphEligible(dictionary)
                    {
                        let str = try Qs.encode(dictionary, options: swiftOptions)
                        return str as NSString
                    }
                }

                // Convert and normalize in one traversal to avoid redundant full-tree walks.
                let bridged = bridgeInputForEncode(object, bridgeUndefined: true)

                // Let the core do its thing (and report EncodeError.cyclicObject if a cycle is present).
                let str = try Qs.encode(bridged, options: swiftOptions)
                return str as NSString
            } catch {
                outError?.pointee = error as NSError
                return nil
            }
        }

        // MARK: - Bridging helpers (Decode path)

        /// Minimal bridging so the Swift core accepts common Obj-C shapes.
        ///
        /// We keep this intentionally lightweight:
        /// - `NSString` → `String`
        /// - `NSDictionary` → `[AnyHashable: Any]` when possible; otherwise re-materialize by copying
        ///   entries (stringifying non-hashable keys if necessary). This keeps decode permissive.
        /// - `NSArray` → `[Any]`
        /// - Scalars pass through
        ///
        /// `forceReduce` can be used to skip the cheap cast and always re-materialize,
        /// which is useful in pathological cases where keys aren’t `AnyHashable`.
        @inline(__always)
        internal static func bridgeInputForDecode(
            _ input: Any?,
            forceReduce: Bool = false
        ) -> Any? {
            guard let input else { return nil }

            // NSString → String
            if let stringValue = input as? NSString { return stringValue as String }

            // NSDictionary → [AnyHashable: Any] (fall back to re-materialization if needed)
            if let dictionary = input as? NSDictionary {
                if !forceReduce, let cast = dictionary as? [AnyHashable: Any] {
                    return cast
                }
                var out: [AnyHashable: Any] = [:]
                dictionary.forEach { key, value in
                    if let hk = key as? AnyHashable {
                        out[hk] = value
                    } else {
                        out[AnyHashable(stringifyKey(key))] = value
                    }
                }
                return out
            }

            // NSArray → [Any]
            if let arrayValue = input as? NSArray { return arrayValue as? [Any] ?? arrayValue.map { $0 } }

            // Numbers, NSNull, etc. can pass through
            return input
        }

        // MARK: - Bridging helpers (Encode path)

        /// Convert Obj-C/Swift containers to **ordered** Swift containers and preserve identity for cycle detection.
        ///
        /// Shapes produced:
        /// - `NSString` → `String`
        /// - `NSDictionary` / `[String: Any]` / `OrderedDictionary<*, Any>` → `OrderedDictionary<String, Any>`
        ///   (keys are stringified with `String(describing:)`)
        /// - `NSArray` / `[Any]` → `[Any]`
        /// - Scalars pass through untouched
        ///
        /// Cycles:
        /// - If we re-encounter the **same** Foundation container instance (`NSDictionary`/`NSArray`),
        ///   we return that instance unchanged to preserve the identity cycle. The core will
        ///   throw `EncodeError.cyclicObject`, which we relay as `NSError`.
        @inline(__always)
        internal static func bridgeInputForEncode(_ input: Any) -> Any {
            bridgeInputForEncode(input, bridgeUndefined: false)
        }

        @inline(__always)
        internal static func bridgeInputForEncode(_ input: Any, bridgeUndefined: Bool) -> Any {
            var seen = Set<ObjectIdentifier>()
            return _bridgeInputForEncode(input, seen: &seen, bridgeUndefined: bridgeUndefined)
        }

        @inline(__always)
        private static func _bridgeInputForEncode(
            _ input: Any,
            seen: inout Set<ObjectIdentifier>,
            bridgeUndefined: Bool
        ) -> Any {
            if bridgeUndefined, input is UndefinedObjC {
                return QsSwift.Undefined.instance
            }

            switch input {
            case let stringValue as NSString:
                return stringValue as String

            case let od as OrderedDictionary<String, Any>:
                var out = OrderedDictionary<String, Any>()
                out.reserveCapacity(od.count)
                for (key, value) in od {
                    out[key] = _bridgeInputForEncode(value, seen: &seen, bridgeUndefined: bridgeUndefined)
                }
                return out

            case let od as OrderedDictionary<AnyHashable, Any>:
                var out = OrderedDictionary<String, Any>()
                out.reserveCapacity(od.count)
                for (key, value) in od {
                    out[stringifyKey(key)] = _bridgeInputForEncode(
                        value,
                        seen: &seen,
                        bridgeUndefined: bridgeUndefined
                    )
                }
                return out

            case let od as OrderedDictionary<NSString, Any>:
                var out = OrderedDictionary<String, Any>()
                out.reserveCapacity(od.count)
                for (nsKey, value) in od {
                    out[nsKey as String] = _bridgeInputForEncode(
                        value,
                        seen: &seen,
                        bridgeUndefined: bridgeUndefined
                    )
                }
                return out

            case let dict as NSDictionary:
                let id = ObjectIdentifier(dict)
                if seen.contains(id) { return dict }
                let inserted = seen.insert(id).inserted
                var out = OrderedDictionary<String, Any>()
                out.reserveCapacity(dict.count)
                let keys = dict.keyEnumerator()
                while let key = keys.nextObject() {
                    guard let value = dict.object(forKey: key) else { continue }
                    out[stringifyKey(key)] = _bridgeInputForEncode(
                        value,
                        seen: &seen,
                        bridgeUndefined: bridgeUndefined
                    )
                }
                if inserted { seen.remove(id) }
                return out

            case let array as NSArray:
                let id = ObjectIdentifier(array)
                if seen.contains(id) { return array }
                let inserted = seen.insert(id).inserted
                var mapped: [Any] = []
                mapped.reserveCapacity(array.count)
                for index in 0..<array.count {
                    mapped.append(
                        _bridgeInputForEncode(
                            array.object(at: index),
                            seen: &seen,
                            bridgeUndefined: bridgeUndefined
                        ))
                }
                if inserted { seen.remove(id) }
                return mapped

            case let dict as [String: Any]:
                var out = OrderedDictionary<String, Any>()
                out.reserveCapacity(dict.count)
                for (key, value) in dict {
                    out[key] = _bridgeInputForEncode(value, seen: &seen, bridgeUndefined: bridgeUndefined)
                }
                return out

            case let array as [Any]:
                var out: [Any] = []
                out.reserveCapacity(array.count)
                for value in array {
                    out.append(_bridgeInputForEncode(value, seen: &seen, bridgeUndefined: bridgeUndefined))
                }
                return out

            default:
                return input
            }
        }

        // MARK: - Undefined bridging (ordered & cycle-aware)

        /// Recursively converts any `UndefinedObjC` to the Swift `Undefined` sentinel,
        /// preserving:
        /// - **Container shape** (keeps `OrderedDictionary` and `[Any]`)
        /// - **Key stringification** (`String(describing:)`)
        /// - **Identity cycles** (returns the original Foundation object when revisiting it)
        @inline(__always)
        internal static func bridgeUndefinedPreservingOrder(_ value: Any?) -> Any? {
            guard let value else { return nil }
            return bridgeInputForEncode(value, bridgeUndefined: true)
        }

        @inline(__always)
        internal static func _bridgeUndefinedPreservingOrder(
            _ value: Any?, seen: inout Set<ObjectIdentifier>
        ) -> Any? {
            guard let value else { return nil }
            return _bridgeInputForEncode(value, seen: &seen, bridgeUndefined: true)
        }

        // MARK: - Narrow ObjC encode fast path

        @inline(__always)
        internal static func _isNarrowObjCEncodeFastPathConfig(_ options: EncodeOptionsObjC?) -> Bool {
            guard let options else { return false }
            guard options.encode == false else { return false }
            guard options.valueEncoderBlock == nil else { return false }
            guard options.dateSerializerBlock == nil else { return false }
            guard options.sortComparatorBlock == nil else { return false }
            guard options.sortKeysCaseInsensitively == false else { return false }
            guard options.filter == nil else { return false }
            guard options.allowDots == false else { return false }
            guard options.encodeDotInKeys == false else { return false }
            guard options.encodeValuesOnly == false else { return false }
            guard options.allowEmptyLists == false else { return false }
            guard options.skipNulls == false else { return false }
            guard options.strictNullHandling == false else { return false }
            guard options.commaRoundTrip == false else { return false }
            guard options.commaCompactNulls == false else { return false }

            let effectiveListFormat: ListFormatObjC = {
                if let listFormat = options.listFormat { return listFormat }
                if let legacyIndices = options.indices {
                    return legacyIndices.boolValue ? .indices : .repeatKey
                }
                return .indices
            }()

            return effectiveListFormat == .indices
        }

        @inline(__always)
        internal static func _isSingleKeyNSDictionaryScalarChainEligible(_ root: NSDictionary) -> Bool {
            var seen = Set<ObjectIdentifier>()
            var cursor = root

            while true {
                let id = ObjectIdentifier(cursor)
                if seen.contains(id) { return false }
                seen.insert(id)

                guard cursor.count == 1 else { return false }

                let keys = cursor.keyEnumerator()
                guard let key = keys.nextObject() else { return false }
                guard let next = cursor.object(forKey: key) else { return false }
                if next is UndefinedObjC { return false }

                if let nextDict = next as? NSDictionary {
                    cursor = nextDict
                    continue
                }

                return !_isNarrowFastPathContainer(next)
            }
        }

        @inline(__always)
        internal static func _isSortedDirectEncodeConfigEligible(_ options: EncodeOptionsObjC?) -> Bool {
            guard let options else { return false }
            guard options.sortComparatorBlock != nil || options.sortKeysCaseInsensitively else {
                return false
            }
            guard options.valueEncoderBlock == nil else { return false }
            guard options.dateSerializerBlock == nil else { return false }
            guard options.filter == nil else { return false }
            return true
        }

        @inline(__always)
        internal static func _isSortedNSStringFoundationGraphEligible(_ root: NSDictionary) -> Bool {
            var stack: [Any] = [root]
            var seen = Set<ObjectIdentifier>()

            while let node = stack.popLast() {
                if node is UndefinedObjC { return false }

                if let dict = node as? NSDictionary {
                    let id = ObjectIdentifier(dict)
                    if seen.contains(id) { return false }
                    seen.insert(id)

                    let keys = dict.keyEnumerator()
                    while let key = keys.nextObject() {
                        guard key is NSString else { return false }
                        guard let value = dict.object(forKey: key) else { return false }
                        stack.append(value)
                    }
                    continue
                }

                if let array = node as? NSArray {
                    let id = ObjectIdentifier(array)
                    if seen.contains(id) { return false }
                    seen.insert(id)

                    for index in 0..<array.count {
                        stack.append(array.object(at: index))
                    }
                    continue
                }

                if _isSortedDirectBypassDisallowedSwiftContainer(node) {
                    return false
                }
            }

            return true
        }

        @inline(__always)
        private static func _isNarrowFastPathContainer(_ value: Any) -> Bool {
            if value is NSDictionary || value is NSArray { return true }
            if value is [String: Any] || value is [AnyHashable: Any] || value is [Any] { return true }
            if value is OrderedDictionary<String, Any> { return true }
            if value is OrderedDictionary<AnyHashable, Any> { return true }
            if value is OrderedDictionary<NSString, Any> { return true }
            return false
        }

        @inline(__always)
        private static func _isSortedDirectBypassDisallowedSwiftContainer(_ value: Any) -> Bool {
            if value is [String: Any] || value is [AnyHashable: Any] || value is [Any] { return true }
            if value is OrderedDictionary<String, Any> { return true }
            if value is OrderedDictionary<AnyHashable, Any> { return true }
            if value is OrderedDictionary<NSString, Any> { return true }
            return false
        }

        // MARK: - Small utils

        /// Consistently stringify any dictionary key (Obj-C or Swift).
        @inline(__always)
        internal static func stringifyKey(_ key: Any) -> String {
            if let key = key as? String { return key }
            if let key = key as? NSString { return key as String }
            if let key = key as? NSNumber { return key.stringValue }
            // We intentionally use `String(describing:)` so non-string keys (NSNumber, NSObject subclasses)
            // become a readable string and round-trip deterministically in the encoder.
            return String(describing: key)
        }
    }
#endif

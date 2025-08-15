import Foundation
import OrderedCollections
import QsSwift

@objc(Qs)
@objcMembers
public final class QsBridge: NSObject {

    // MARK: - Decode

    public static func decode(
        _ input: Any?,
        options: DecodeOptionsObjC? = nil,
        error outError: NSErrorPointer = nil
    ) -> NSDictionary? {
        do {
            let bridged = bridgeInputForDecode(input)
            let result = try Qs.decode(bridged, options: options?.swift ?? QsSwift.DecodeOptions())
            return result as NSDictionary
        } catch {
            outError?.pointee = error as NSError
            return nil
        }
    }

    // MARK: - Encode

    public static func encode(
        _ object: Any, options: EncodeOptionsObjC? = nil, error outError: NSErrorPointer = nil
    ) -> NSString? {
        do {
            // 1) Convert everything to Swift containers, using OrderedDictionary and preserving identity for cycles
            let ordered = bridgeInputForEncode(object)

            // 2) Bridge Undefined while preserving ordered shape and cycles
            let bridged = bridgeUndefinedPreservingOrder(ordered) ?? ordered

            // 3) Let the core do its thing (and report cyclicObject if present)
            let str = try Qs.encode(bridged, options: options?.swift ?? QsSwift.EncodeOptions())
            return str as NSString
        } catch {
            outError?.pointee = error as NSError
            return nil
        }
    }

    // MARK: - Bridging helpers

    /// Minimal bridging so the core accepts common Obj-C shapes.
    @inline(__always)
    internal static func bridgeInputForDecode(
        _ input: Any?,
        forceReduce: Bool = false  // ← NEW
    ) -> Any? {
        guard let input else { return nil }

        // Strings must become Swift.String
        if let s = input as? NSString { return s as String }

        // NSDictionary → [AnyHashable: Any] (core will stringify keys)
        if let d = input as? NSDictionary {
            if !forceReduce, let cast = d as? [AnyHashable: Any] {
                return cast
            }
            return d.reduce(into: [AnyHashable: Any]()) { acc, kv in
                if let (k, v) = kv as? (AnyHashable, Any) {
                    acc[k] = v
                } else {
                    acc[AnyHashable(String(describing: kv.key))] = kv.value
                }
            }
        }

        // NSArray → [Any]
        if let a = input as? NSArray { return a as? [Any] ?? a.map { $0 } }

        // Numbers, NSNull, etc. can pass through
        return input
    }

    @inline(__always)
    internal static func bridgeInputForEncode(_ input: Any) -> Any {
        let seen = NSHashTable<AnyObject>.weakObjects()
        return _bridgeInputForEncode(input, seen: seen)
    }

    @inline(__always)
    private static func _bridgeInputForEncode(_ input: Any, seen: NSHashTable<AnyObject>) -> Any {
        switch input {
        case let s as NSString:
            return s as String

        case let od as OrderedDictionary<String, Any>:
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(od.count)
            for (k, v) in od { out[k] = _bridgeInputForEncode(v, seen: seen) }
            return out

        case let od as OrderedDictionary<NSString, Any>:
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(od.count)
            for (k, v) in od { out[k as String] = _bridgeInputForEncode(v, seen: seen) }
            return out

        case let d as NSDictionary:
            let obj = d as AnyObject
            if seen.contains(obj) {
                // Cycle detected: keep the original reference so the core can report cyclicObject.
                return d
            }
            seen.add(obj)

            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(d.count)
            d.forEach { (k, v) in
                out[String(describing: k)] = _bridgeInputForEncode(v, seen: seen)
            }
            return out

        case let a as NSArray:
            let obj = a as AnyObject
            if seen.contains(obj) {
                return a
            }
            seen.add(obj)
            return a.map { _bridgeInputForEncode($0, seen: seen) }

        case let d as [String: Any]:
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(d.count)
            for (k, v) in d { out[k] = _bridgeInputForEncode(v, seen: seen) }
            return out

        case let a as [Any]:
            return a.map { _bridgeInputForEncode($0, seen: seen) }

        default:
            return input
        }
    }

    @inline(__always)
    private static func bridgeUndefinedPreservingOrder(_ v: Any?) -> Any? {
        let seen = NSHashTable<AnyObject>.weakObjects()
        return _bridgeUndefinedPreservingOrder(v, seen: seen)
    }

    @inline(__always)
    private static func _bridgeUndefinedPreservingOrder(_ v: Any?, seen: NSHashTable<AnyObject>)
        -> Any?
    {
        switch v {
        case is UndefinedObjC:
            return QsSwift.Undefined.instance

        case let od as OrderedDictionary<String, Any>:
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(od.count)
            for (k, val) in od {
                out[k] = _bridgeUndefinedPreservingOrder(val, seen: seen) ?? val
            }
            return out

        case let od as OrderedDictionary<NSString, Any>:
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(od.count)
            for (k, val) in od {
                out[k as String] = _bridgeUndefinedPreservingOrder(val, seen: seen) ?? val
            }
            return out

        case let d as NSDictionary:
            let obj = d as AnyObject
            if seen.contains(obj) { return d }  // keep cycles
            seen.add(obj)
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(d.count)
            d.forEach { (k, val) in
                out[String(describing: k)] = _bridgeUndefinedPreservingOrder(val, seen: seen) ?? val
            }
            return out

        case let a as NSArray:
            let obj = a as AnyObject
            if seen.contains(obj) { return a }
            seen.add(obj)
            return a.map { _bridgeUndefinedPreservingOrder($0, seen: seen) ?? $0 }

        case let d as [String: Any]:
            var out = OrderedDictionary<String, Any>()
            out.reserveCapacity(d.count)
            for (k, val) in d {
                out[k] = _bridgeUndefinedPreservingOrder(val, seen: seen) ?? val
            }
            return out

        case let a as [Any]:
            return a.map { _bridgeUndefinedPreservingOrder($0, seen: seen) ?? $0 }

        default:
            return v
        }
    }

    /// Recursively converts any `QsUndefined` (Obj-C) instances to the Swift `Undefined` sentinel,
    /// preserving container shape (always returns Swift `[String: Any]` / `[Any]` where possible).
    @inline(__always)
    private static func _bridgeUndefined(_ v: Any?) -> Any? {
        // kick off with a fresh identity set
        let seen = NSHashTable<AnyObject>.weakObjects()
        return _bridgeUndefined(v, seen: seen)
    }

    @inline(__always)
    private static func _bridgeUndefined(_ v: Any?, seen: NSHashTable<AnyObject>) -> Any? {
        switch v {
        // ObjC sentinel → Swift sentinel
        case is UndefinedObjC:
            return QsSwift.Undefined.instance

        // --- Foundation containers FIRST (so we can use identity to break cycles) ---

        case let d as NSDictionary:
            // If we've already seen this *exact* object, preserve the reference to keep the cycle;
            // the core encoder will detect/throw on it later.
            let obj = d as AnyObject
            if seen.contains(obj) { return d }
            seen.add(obj)

            var out: [String: Any] = [:]
            out.reserveCapacity(d.count)
            d.forEach { k, val in
                out[String(describing: k)] = _bridgeUndefined(val, seen: seen) ?? val
            }
            return out

        case let a as NSArray:
            let obj = a as AnyObject
            if seen.contains(obj) { return a }
            seen.add(obj)
            return a.map { _bridgeUndefined($0, seen: seen) ?? $0 } as [Any]

        // --- Pure Swift containers (value types; no identity cycles) ---

        case let d as [String: Any]:
            var out: [String: Any] = [:]
            out.reserveCapacity(d.count)
            for (k, val) in d {
                out[k] = _bridgeUndefined(val, seen: seen) ?? val
            }
            return out

        case let a as [Any]:
            return a.map { _bridgeUndefined($0, seen: seen) ?? $0 }

        default:
            return v
        }
    }
}

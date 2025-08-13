import Foundation
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
            // 1) Normalize ObjC → Swift containers
            let normalized = bridgeInputForEncode(object)
            // 2) Bridge QsUndefined across the object graph
            let bridged = _bridgeUndefined(normalized) ?? normalized

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
    internal static func bridgeInputForDecode(_ input: Any?) -> Any? {
        guard let input else { return nil }

        // Strings must become Swift.String
        if let s = input as? NSString { return s as String }

        // NSDictionary → [AnyHashable: Any] (core will stringify keys)
        if let d = input as? NSDictionary {
            return d as? [AnyHashable: Any]
                ?? d.reduce(into: [AnyHashable: Any]()) { acc, kv in
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

    /// Normalizes common Objective-C shapes to the Swift containers expected by the core encoder:
    /// - NSString → String
    /// - NSDictionary → [String: Any] (all keys stringified via `String(describing:)`)
    /// - NSArray → [Any]
    /// Everything else is returned as-is.
    @inline(__always)
    internal static func bridgeInputForEncode(_ input: Any) -> Any {
        // NSString → String
        if let s = input as? NSString { return s as String }

        // NSDictionary → [String: Any] (stringify *all* keys)
        if let d = input as? NSDictionary {
            var out = [String: Any]()
            out.reserveCapacity(d.count)
            d.forEach { (k, v) in out[String(describing: k)] = v }
            return out
        }

        // NSArray → [Any]
        if let a = input as? NSArray { return a as? [Any] ?? a.map { $0 } }

        // Already a Swift container / value? Just return it.
        return input
    }

    /// Recursively converts any `QsUndefined` (Obj-C) instances to the Swift `Undefined` sentinel,
    /// preserving container shape (always returns Swift `[String: Any]` / `[Any]` where possible).
    @inline(__always)
    private static func _bridgeUndefined(_ v: Any?) -> Any? {
        switch v {

        // ObjC sentinel → Swift sentinel
        case is UndefinedObjC:
            return QsSwift.Undefined.instance

        // Swift containers
        case let d as [String: Any]:
            var out: [String: Any] = [:]
            out.reserveCapacity(d.count)
            for (k, val) in d { out[k] = _bridgeUndefined(val) ?? val }
            return out

        case let a as [Any]:
            return a.map { _bridgeUndefined($0) ?? $0 }

        // Foundation containers (defensive)
        case let d as NSDictionary:
            var out: [String: Any] = [:]
            out.reserveCapacity(d.count)
            d.forEach { k, val in out[String(describing: k)] = _bridgeUndefined(val) ?? val }
            return out

        case let a as NSArray:
            return a.map { _bridgeUndefined($0) ?? $0 } as [Any]

        default:
            return v
        }
    }
}

import Foundation
import OrderedCollections

@testable import QsObjC

/// Build ordered maps from Obj-C.
@objc(SPMOrdered)
public final class SPMOrdered: NSObject {
    /// Makes an OrderedDictionary<String, Any> but returns it as `Any` so Obj-C can hold it.
    @objc public static func dictWithKeys(_ keys: [NSString], values: [Any]) -> Any {
        var od = OrderedDictionary<String, Any>()
        let n = min(keys.count, values.count)
        for i in 0..<n { od[keys[i] as String] = values[i] }
        return od
    }
}

/// Thin wrappers so Obj-C doesn’t deal with Swift `throws`.
@objc(QsObjCTestHelpers)
public final class QsObjCTestHelpers: NSObject {
    @objc public static func encode(_ obj: Any, options: EncodeOptionsObjC?) -> NSString? {
        QsBridge.encode(obj, options: options, error: nil)
    }
    @objc public static func decode(_ s: NSString) -> NSDictionary? {
        QsBridge.decode(s, options: nil, error: nil)
    }

    /// Deep equality: compares a Swift OrderedDictionary tree (lhs) to NSDictionary/NSArray (rhs).
    @objc public static func deepEqualOrdered(_ lhs: Any, rhs: NSDictionary) -> Bool {
        func norm(_ x: Any) -> Any {
            switch x {
            case let od as OrderedDictionary<String, Any>:
                var out: [String: Any] = [:]
                out.reserveCapacity(od.count)
                for (k, v) in od { out[k] = norm(v) }
                return out
            case let d as [String: Any]:
                var out: [String: Any] = [:]
                d.forEach { out[$0.key] = norm($0.value) }
                return out
            case let a as [Any]:
                return a.map { norm($0) }
            case let nsd as NSDictionary:
                var out: [String: Any] = [:]
                nsd.forEach { (k, v) in out[String(describing: k)] = norm(v) }
                return out
            case let nsa as NSArray:
                return nsa.map { norm($0) }
            default:
                return x
            }
        }
        let L = norm(lhs)
        let R = norm(rhs)
        if let dl = L as? [String: Any], let dr = R as? [String: Any] {
            return NSDictionary(dictionary: dl).isEqual(to: dr)
        }
        if let al = L as? [Any], let ar = R as? [Any] {
            return NSArray(array: al).isEqual(to: ar)
        }
        return false
    }
}

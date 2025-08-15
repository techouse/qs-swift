import Foundation
import OrderedCollections

/// Recursively convert OrderedDictionary → [String: Any] and normalize nested values.
/// Arrays and dictionaries are normalized recursively. NSNull is preserved.
public func normalizeToStdDict(_ any: Any?) -> Any? {
    guard let any = any else { return nil }

    // OrderedDictionary<String, Any> → [String: Any] (recursive)
    if let od = any as? OrderedDictionary<String, Any> {
        var out: [String: Any] = [:]
        out.reserveCapacity(od.count)
        for (k, v) in od {
            out[k] = normalizeToStdDict(v) ?? NSNull()
        }
        return out
    }

    // [String: Any] → recursively normalize values
    if let dict = any as? [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict {
            out[k] = normalizeToStdDict(v) ?? NSNull()
        }
        return out
    }

    // [Any] → recursively normalize elements
    if let arr = any as? [Any] {
        return arr.map { normalizeToStdDict($0) ?? NSNull() }
    }

    // Already a scalar (String/Number/Bool/Date/NSNull/etc)
    return any
}

/// Container-agnostic deep equality:
/// - treats OrderedDictionary and [String: Any] as equivalent maps
/// - compares arrays element-wise
/// - compares scalars by NSNumber/NSString semantics where possible
public func deepEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (normalizeToStdDict(lhs), normalizeToStdDict(rhs)) {
    case (nil, nil):
        return true
    case (let la as [String: Any], let lb as [String: Any]):
        guard la.count == lb.count else { return false }
        for (k, va) in la {
            guard let vb = lb[k], deepEqual(va, vb) else { return false }
        }
        return true
    case (let la as [Any], let lb as [Any]):
        guard la.count == lb.count else { return false }
        for (a, b) in zip(la, lb) where !deepEqual(a, b) { return false }
        return true
    case (let a as NSNumber, let b as NSNumber):
        // Handles Int/Double/Bool interop (Bool is an NSNumber too)
        return a == b
    case (let a as NSString, let b as NSString):
        return a == b
    case (let a?, let b?):
        // Fallback to String(describing:) for miscellaneous Equatable-s via bridge
        return String(describing: a) == String(describing: b)
    default:
        return false
    }
}

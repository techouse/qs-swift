import Foundation

extension Utils {
    @inline(__always)
    private static func foundationContainerID(_ value: Any) -> ObjectIdentifier? {
        guard Swift.type(of: value) is AnyClass else { return nil }
        if let dict = value as? NSDictionary {
            return ObjectIdentifier(dict)
        }
        if let array = value as? NSArray {
            return ObjectIdentifier(array)
        }
        return nil
    }

    /// Compact a nested structure by removing all `Undefined` values.
    /// - Note: `NSNull()` is preserved (represents an explicit `null`).
    /// - If `allowSparseLists` is `false` (default), array holes are *removed* (indexes shift).
    /// - If `allowSparseLists` is `true`, holes are kept as `NSNull()` (Swift arrays can't be truly sparse).
    @usableFromInline
    static func compact(
        _ root: inout [String: Any?],
        allowSparseLists: Bool = false
    ) -> [String: Any?] {
        var activeFoundationContainers: Set<ObjectIdentifier> = []

        @inline(__always)
        func compactEntries(
            _ entries: [(String, Any?)],
            allowSparse: Bool
        ) -> [String: Any?] {
            var out: [String: Any?] = [:]
            out.reserveCapacity(entries.count)
            for (key, rawValue) in entries {
                if let compacted = compactValue(rawValue, allowSparse: allowSparse) {
                    out[key] = compacted
                }
            }
            return out
        }

        @inline(__always)
        func compactElements(
            count: Int,
            allowSparse: Bool,
            _ visit: (@escaping (Any?) -> Void) -> Void
        ) -> [Any] {
            var out: [Any] = []
            out.reserveCapacity(count)
            visit { rawElement in
                let element = Utils.eraseOptionalElement(rawElement)
                if element is Undefined {
                    if allowSparse { out.append(NSNull()) }
                    return
                }
                guard let element else {
                    out.append(NSNull())
                    return
                }
                if let compacted = compactValue(element, allowSparse: allowSparse) {
                    out.append(compacted)
                }
            }
            return out
        }

        @inline(__always)
        func compactValue(_ rawValue: Any?, allowSparse: Bool) -> Any? {
            let value = Utils.eraseOptionalLike(rawValue)

            // Drop Undefined entirely
            if value is Undefined { return nil }
            guard let value else { return nil }

            let foundationID = Utils.foundationContainerID(value)
            if let foundationID {
                guard activeFoundationContainers.insert(foundationID).inserted else {
                    return NSNull()
                }
            }
            defer {
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                }
            }

            if let compacted = Utils.withExactStringifiedEntries(
                value,
                { entries in
                    compactEntries(entries, allowSparse: allowSparse)
                })
            {
                return compacted
            }

            if let compacted = Utils.withExactArrayElements(
                value,
                { count, visit in
                    compactElements(count: count, allowSparse: allowSparse, visit)
                })
            {
                return compacted
            }

            // Primitive (String/Number/Bool/Date/URL/NSNull/etc)
            return value
        }

        var newRoot: [String: Any?] = [:]
        newRoot.reserveCapacity(root.count)
        for (key, value) in root {
            if let cv = compactValue(value, allowSparse: allowSparseLists) {
                newRoot[key] = cv
            }
        }
        root = newRoot
        return root
    }

    /// Remove `Undefined`, coerce optionals to concrete `Any`, keep `NSNull`,
    /// and (optionally) preserve sparse arrays with `NSNull()` placeholders.
    @usableFromInline
    static func compactToAny(
        _ root: [String: Any?],
        allowSparseLists: Bool
    ) -> [String: Any] {
        var activeFoundationContainers: Set<ObjectIdentifier> = []

        func normalizeEntries(_ entries: [(String, Any?)]) -> [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(entries.count)
            for (key, child) in entries {
                guard let normalized = normalizeValue(child) else { continue }
                out[key] = normalized
            }
            return out
        }

        func normalizeArray(
            count: Int,
            _ visit: (@escaping (Any?) -> Void) -> Void
        ) -> [Any] {
            var out: [Any] = []
            out.reserveCapacity(count)

            visit { rawElement in
                let element = Utils.eraseOptionalElement(rawElement)
                if element is Undefined {
                    if allowSparseLists { out.append(NSNull()) }
                    return
                }

                guard let normalized = normalizeValue(element) else { return }
                out.append(normalized)
            }
            return out
        }

        func normalizeValue(_ rawValue: Any?) -> Any? {
            let value = Utils.eraseOptionalLike(rawValue)

            switch value {
            case is Undefined:
                return nil
            case let value?:
                let foundationID = Utils.foundationContainerID(value)
                if let foundationID {
                    guard activeFoundationContainers.insert(foundationID).inserted else {
                        return NSNull()
                    }
                }
                defer {
                    if let foundationID {
                        activeFoundationContainers.remove(foundationID)
                    }
                }

                if let normalized = Utils.withExactStringifiedEntries(
                    value,
                    { entries in
                        normalizeEntries(entries)
                    })
                {
                    return normalized
                }

                if let normalized = Utils.withExactArrayElements(
                    value,
                    { count, visit in
                        normalizeArray(count: count, visit)
                    })
                {
                    return normalized
                }

                return value
            case .none:
                return NSNull()
            }
        }

        var out: [String: Any] = [:]
        out.reserveCapacity(root.count)

        for (key, value) in root {
            guard let normalized = normalizeValue(value) else { continue }
            out[key] = normalized
        }
        return out
    }
}

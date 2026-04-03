import Foundation

extension Utils {
    /// Compact a nested structure by removing all `Undefined` values.
    /// - Note: `NSNull()` is preserved (represents an explicit `null`).
    /// - If `allowSparseLists` is `false` (default), array holes are *removed* (indexes shift).
    /// - If `allowSparseLists` is `true`, holes are kept as `NSNull()` (Swift arrays can't be truly sparse).
    @usableFromInline
    static func compact(
        _ root: inout [String: Any?],
        allowSparseLists: Bool = false
    ) -> [String: Any?] {
        @inline(__always)
        func compactValue(_ value: Any?, allowSparse: Bool) -> Any? {
            // Drop Undefined entirely
            if value is Undefined { return nil }

            if let object = value, Swift.type(of: object) is AnyClass {
                if let dict = object as? NSDictionary {
                    var out: [String: Any?] = [:]
                    out.reserveCapacity(dict.count)
                    for (rawKey, rawValue) in dict {
                        if let keyHash = rawKey as? AnyHashable, Utils.isOverflowKey(keyHash) { continue }
                        let key = String(describing: rawKey)
                        if let cv = compactValue(rawValue, allowSparse: allowSparse) {
                            out[key] = cv
                        }
                    }
                    return out
                }

                if let array = object as? NSArray {
                    var out: [Any] = []
                    out.reserveCapacity(array.count)
                    for element in array {
                        if let cv = compactValue(element, allowSparse: allowSparse) {
                            out.append(cv)
                        } else if allowSparse {
                            out.append(NSNull())
                        }
                    }
                    return out
                }
            }

            // Dictionary branch
            if let dict = value as? [String: Any?] {
                var out: [String: Any?] = [:]
                out.reserveCapacity(dict.count)
                for (key, val) in dict {
                    if let cv = compactValue(val, allowSparse: allowSparse) {
                        out[key] = cv
                    }
                    // else: value was Undefined → remove the key
                }
                return out
            }

            if let dict = value as? [AnyHashable: Any?] {
                var out: [String: Any?] = [:]
                out.reserveCapacity(dict.count)
                for (rawKey, val) in dict {
                    if Utils.isOverflowKey(rawKey) { continue }
                    let key = String(describing: rawKey)
                    if let cv = compactValue(val, allowSparse: allowSparse) {
                        out[key] = cv
                    }
                }
                return out
            }

            if let dict = value as? [AnyHashable: Any] {
                var out: [String: Any?] = [:]
                out.reserveCapacity(dict.count)
                for (rawKey, val) in dict {
                    if Utils.isOverflowKey(rawKey) { continue }
                    let key = String(describing: rawKey)
                    if let cv = compactValue(val, allowSparse: allowSparse) {
                        out[key] = cv
                    }
                }
                return out
            }

            // Array branches – tolerate both [Any] and [Any?] shapes.
            if let arrOpt = value as? [Any?] {
                var out: [Any] = []
                out.reserveCapacity(arrOpt.count)
                for element in arrOpt {
                    guard let unwrapped = element else {
                        out.append(NSNull())
                        continue
                    }
                    if unwrapped is Undefined {
                        if allowSparse { out.append(NSNull()) }
                        continue
                    }
                    if let subDict = unwrapped as? [String: Any?] {
                        if let cv = compactValue(subDict, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArr = unwrapped as? [Any] {
                        if let cv = compactValue(subArr, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArrOpt2 = unwrapped as? [Any?] {
                        if let cv = compactValue(subArrOpt2, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else {
                        out.append(unwrapped)
                    }
                }
                return out
            }

            if let arr = value as? [Any] {
                var out: [Any] = []
                out.reserveCapacity(arr.count)
                for element in arr {
                    if element is Undefined {
                        if allowSparse { out.append(NSNull()) }
                        // else: drop it
                        continue
                    }
                    if let subDict = element as? [String: Any?] {
                        if let cv = compactValue(subDict, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArr = element as? [Any] {
                        if let cv = compactValue(subArr, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArrOpt = element as? [Any?] {
                        if let cv = compactValue(subArrOpt, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else {
                        out.append(element)
                    }
                }
                return out
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
        func normalizeArray(_ arr: [Any?]) -> [Any] {
            var out: [Any] = []
            out.reserveCapacity(arr.count)

            for el in arr {
                switch el {
                case is Undefined:
                    if allowSparseLists { out.append(NSNull()) }
                // else: drop it
                case let dict as [String: Any?]:
                    out.append(compactToAny(dict, allowSparseLists: allowSparseLists))
                case let arrayOpt as [Any?]:
                    out.append(normalizeArray(arrayOpt))
                case .some(let value):
                    out.append(value)
                case .none:
                    // explicit nil → NSNull so we can keep `[Any]`
                    out.append(NSNull())
                }
            }
            return out
        }

        func normalizeValue(_ value: Any?) -> Any? {
            switch value {
            case is Undefined:
                return nil
            case let dict as [String: Any?]:
                return compactToAny(dict, allowSparseLists: allowSparseLists)
            case let dict as [AnyHashable: Any?]:
                var bridged: [String: Any?] = [:]
                bridged.reserveCapacity(dict.count)
                for (key, child) in dict {
                    if Utils.isOverflowKey(key) { continue }
                    bridged[String(describing: key)] = child
                }
                return compactToAny(bridged, allowSparseLists: allowSparseLists)
            case let dict as [AnyHashable: Any]:
                var bridged: [String: Any?] = [:]
                bridged.reserveCapacity(dict.count)
                for (key, child) in dict {
                    if Utils.isOverflowKey(key) { continue }
                    bridged[String(describing: key)] = child
                }
                return compactToAny(bridged, allowSparseLists: allowSparseLists)
            case let arrayOpt as [Any?]:
                return normalizeArray(arrayOpt)
            case let array as [Any]:
                return normalizeArray(array.map(Optional.some))
            case let object? where Swift.type(of: object) is AnyClass:
                if let dict = object as? NSDictionary {
                    var bridged: [String: Any?] = [:]
                    bridged.reserveCapacity(dict.count)
                    for (rawKey, child) in dict {
                        if let keyHash = rawKey as? AnyHashable, Utils.isOverflowKey(keyHash) { continue }
                        bridged[String(describing: rawKey)] = child
                    }
                    return compactToAny(bridged, allowSparseLists: allowSparseLists)
                }
                if let array = object as? NSArray {
                    return normalizeArray(array.map(Optional.some))
                }
                return object
            case .some(let value):
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

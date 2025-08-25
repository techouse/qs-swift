import Foundation
import OrderedCollections

extension QsSwift.Utils {
    /// Merges two objects, where the source object overrides the target object.
    /// If the source is a Dictionary, it will merge its entries into the target.
    /// If the source is an Array, it will append its items to the target.
    /// If the source is a primitive, it will replace the target.
    ///
    /// - Parameters:
    ///   - target: The target object to merge into.
    ///   - source: The source object to merge from.
    ///   - options: Optional decode options for merging behavior.
    /// - Returns: The merged object.
    @usableFromInline
    static func merge(target: Any?, source: Any?, options: DecodeOptions = DecodeOptions()) -> Any? {
        guard let source = source else { return target }

        if let tArr = target as? [Any?], let sDict = source as? [AnyHashable: Any] {
            var tDict: [AnyHashable: Any] = [:]
            for (idx, element) in tArr.enumerated() where !(element is Undefined) {
                tDict[idx] = element ?? NSNull()
            }
            for (key, value) in sDict { tDict[key] = value }
            return tDict
        }

        if let tDict = target as? [AnyHashable: Any], let sArr = source as? [Any?] {
            var sDict: [AnyHashable: Any] = [:]
            for (idx, element) in sArr.enumerated() where !(element is Undefined) {
                sDict[idx] = element ?? NSNull()
            }
            return merge(target: tDict, source: sDict, options: options)
        }

        if !(source is [AnyHashable: Any]) {
            if var targetOSet = target as? OrderedSet<AnyHashable> {
                if let sourceOSet = source as? OrderedSet<AnyHashable> {
                    targetOSet.formUnion(sourceOSet)  // keeps first-seen order
                    return targetOSet
                } else if let seq = asSequence(source) {
                    for el in seq where !(el is Undefined) {
                        if let hashable = el as? AnyHashable { _ = targetOSet.updateOrAppend(hashable) }
                    }
                    return targetOSet
                } else if source is Undefined {
                    return targetOSet
                } else if let hashable = source as? AnyHashable {
                    _ = targetOSet.updateOrAppend(hashable)
                    return targetOSet
                }
            }

            if var targetSet = target as? Set<AnyHashable> {
                if let sourceSet = source as? Set<AnyHashable> {
                    return targetSet.union(sourceSet)
                } else if let seq = asSequence(source) {
                    let items =
                        seq
                        .filter { !($0 is Undefined) }
                        .compactMap { $0 as? AnyHashable }
                    return targetSet.union(items)
                } else if source is Undefined {
                    return targetSet
                } else {
                    if let hashable = source as? AnyHashable { targetSet.insert(hashable) }
                    return targetSet
                }
            }

            if let targetArray = target as? [Any] {
                if targetArray.contains(where: { $0 is Undefined }) {
                    var mutableTarget: [Int: Any?] = [:]

                    for (index, value) in targetArray.enumerated() {
                        mutableTarget[index] = value
                    }

                    if let seq = asSequence(source) {
                        for (index, item) in seq.enumerated() where !(item is Undefined) {
                            mutableTarget[index] = item
                        }
                    } else {
                        mutableTarget[mutableTarget.count] = source
                    }

                    if !options.parseLists
                        && mutableTarget.values.contains(where: { $0 is Undefined })
                    {
                        // Preserve original element order by iterating indices in ascending order.
                        // Drop both `nil` and `Undefined` entries to match prior semantics.
                        let orderedIndices = mutableTarget.keys.sorted()
                        let pruned: [Any] = orderedIndices.compactMap { idx in
                            guard let value = mutableTarget[idx] else { return nil }
                            return (value is Undefined) ? nil : value
                        }
                        return pruned
                    }

                    if target is Set<AnyHashable> {
                        return Set(mutableTarget.values.compactMap { $0 as? AnyHashable })
                    }

                    return mutableTarget.sorted { $0.key < $1.key }.map(\.value)
                } else {
                    if let seq = asSequence(source) {
                        let targetMaps = targetArray.allSatisfy {
                            $0 is [AnyHashable: Any] || $0 is Undefined
                        }
                        let sourceMaps = seq.allSatisfy {
                            $0 is [AnyHashable: Any] || $0 is Undefined
                        }

                        if targetMaps && sourceMaps {
                            var mutableTarget: [Int: Any?] = [:]

                            for (index, value) in targetArray.enumerated() {
                                mutableTarget[index] = value
                            }

                            for (index, item) in seq.enumerated() {
                                if let existing = mutableTarget[index] {
                                    mutableTarget[index] = merge(
                                        target: existing, source: item, options: options)
                                } else {
                                    mutableTarget[index] = item
                                }
                            }

                            return mutableTarget.sorted { $0.key < $1.key }.map(\.value)
                        } else {
                            let filtered = seq.filter { !($0 is Undefined) }
                            return targetArray + filtered
                        }
                    } else {
                        if var targetOSet = target as? OrderedSet<AnyHashable>,
                            let hashable = source as? AnyHashable
                        {
                            _ = targetOSet.updateOrAppend(hashable)
                            return targetOSet
                        }
                        if let targetSet = target as? Set<AnyHashable>,
                            let hashable = source as? AnyHashable
                        {
                            return targetSet.union([hashable])
                        }
                        return targetArray + [source]
                    }
                }
            } else if let targetDict = target as? [AnyHashable: Any] {
                var mutableTarget = targetDict

                if let seq = asSequence(source) {
                    for (index, item) in seq.enumerated() where !(item is Undefined) {
                        mutableTarget[index] = item
                    }
                } else if !(source is Undefined) {
                    let key = String(describing: source)
                    if !key.isEmpty { mutableTarget[key] = true }
                }

                return mutableTarget
            } else {
                if let seq = asSequence(source) {
                    let filtered = seq.filter { !($0 is Undefined) }
                    var result: [Any?] = [target]  // preserve nil at index 0
                    result.append(contentsOf: filtered)
                    return result
                }
                return [target as Any?, source as Any?]
            }
        }

        if target == nil || !(target is [AnyHashable: Any]) {
            if let targetArray = target as? [Any] {
                var mutableTarget: [AnyHashable: Any] = [:]
                for (index, value) in targetArray.enumerated() where !(value is Undefined) {
                    mutableTarget[index] = value
                }

                if let sourceDict = source as? [AnyHashable: Any] {
                    for (key, value) in sourceDict {
                        mutableTarget[key] = value
                    }
                }
                return mutableTarget
            } else {
                var mutableTarget: [Any] = []
                if let target = target {
                    mutableTarget.append(target)
                }

                if let sourceArray = source as? [Any] {
                    mutableTarget.append(contentsOf: sourceArray.filter { !($0 is Undefined) })
                } else {
                    mutableTarget.append(source)
                }

                return mutableTarget
            }
        }

        var mergeTarget: [AnyHashable: Any]

        if let targetArray = target as? [Any], asSequence(source) == nil {
            mergeTarget = [:]
            for (index, value) in targetArray.enumerated() where !(value is Undefined) {
                mergeTarget[index] = value
            }
        } else {
            // This branch should only be reached when `target` is a dictionary.
            // Use a guarded cast to satisfy SwiftLint (no force_cast) but keep the
            // original behavior (trap) if the invariant is broken.
            guard let dict = target as? [AnyHashable: Any] else {
                preconditionFailure("Utils.merge: expected target to be [AnyHashable: Any] in merge()")
            }
            mergeTarget = dict
        }

        if let sourceDict = source as? [AnyHashable: Any] {
            for (key, value) in sourceDict {
                if let existingValue = mergeTarget[key] {
                    mergeTarget[key] = merge(target: existingValue, source: value, options: options)
                } else {
                    mergeTarget[key] = value
                }
            }
        }

        return mergeTarget
    }

    // MARK: - Sequence Helpers

    /// Converts a value to a sequence (array) if it is an array, ordered set, or set.
    private static func asSequence(_ value: Any) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let orderedSet = value as? OrderedSet<AnyHashable> { return Array(orderedSet) }
        if let setValues = value as? Set<AnyHashable> { return Array(setValues) }
        return nil
    }
}

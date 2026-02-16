// swiftlint:disable file_length
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
            var maxIndex = -1

            for (idx, element) in tArr.enumerated() where !(element is Undefined) {
                tDict[idx] = element ?? NSNull()
                if idx > maxIndex { maxIndex = idx }
            }

            for (key, value) in sDict where !Utils.isOverflowKey(key) {
                tDict[key] = value
                if let idx = Utils.intIndex(key), idx > maxIndex {
                    maxIndex = idx
                }
            }

            if Utils.isOverflow(sDict) {
                if let sourceMax = Utils.overflowMaxIndex(sDict), sourceMax > maxIndex {
                    maxIndex = sourceMax
                }
                Utils.setOverflowMaxIndex(&tDict, maxIndex)
            }
            return tDict
        }

        if let tDict = target as? [AnyHashable: Any], let sArr = source as? [Any?] {
            if Utils.isOverflow(tDict) {
                var overflow = tDict
                var maxIndex = Utils.overflowMaxIndex(overflow) ?? -1
                for element in sArr where !(element is Undefined) {
                    maxIndex += 1
                    overflow[maxIndex] = element ?? NSNull()
                }
                Utils.setOverflowMaxIndex(&overflow, maxIndex)
                return overflow
            }
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

                    // We’re in the Array-target branch. `target` cannot be a Set/OrderedSet here.
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
                                    mutableTarget[index] = mergeValues(
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
                        // source is not a sequence and we are in the Array-target branch; target cannot be any Set/OrderedSet here.
                        return targetArray + [source]
                    }
                }
            } else if let targetDict = target as? [AnyHashable: Any] {
                if Utils.isOverflow(targetDict) {
                    var overflow = targetDict
                    var maxIndex = Utils.overflowMaxIndex(overflow) ?? -1

                    if let seq = asSequence(source) {
                        for item in seq where !(item is Undefined) {
                            maxIndex += 1
                            overflow[maxIndex] = item
                        }
                    } else if !(source is Undefined) {
                        maxIndex += 1
                        overflow[maxIndex] = source
                    }

                    Utils.setOverflowMaxIndex(&overflow, maxIndex)
                    return overflow
                }

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
            if let sourceDict = source as? [AnyHashable: Any], Utils.isOverflow(sourceDict) {
                if let targetArray = target as? [Any] {
                    var mutableTarget: [AnyHashable: Any] = [:]
                    var maxIndex = -1
                    for (index, value) in targetArray.enumerated() where !(value is Undefined) {
                        mutableTarget[index] = value
                        if index > maxIndex { maxIndex = index }
                    }
                    for (key, value) in sourceDict where !Utils.isOverflowKey(key) {
                        mutableTarget[key] = value
                        if let idx = Utils.intIndex(key), idx > maxIndex {
                            maxIndex = idx
                        }
                    }
                    Utils.setOverflowMaxIndex(&mutableTarget, maxIndex)
                    return mutableTarget
                }

                var result: [AnyHashable: Any] = [:]
                if let target = target {
                    result[0] = target
                } else {
                    result[0] = NSNull()
                }

                for (key, value) in sourceDict where !Utils.isOverflowKey(key) {
                    if let idx = Utils.intIndex(key) {
                        result[idx + 1] = value
                    } else {
                        result[key] = value
                    }
                }

                let newMax = (Utils.overflowMaxIndex(sourceDict) ?? -1) + 1
                return Utils.markOverflow(result, maxIndex: newMax)
            }

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
            return mergeDictionariesIterative(target: mergeTarget, source: sourceDict, options: options)
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

    @inline(__always)
    private static func mergeValues(target: Any?, source: Any?, options: DecodeOptions) -> Any? {
        if let targetDict = target as? [AnyHashable: Any], let sourceDict = source as? [AnyHashable: Any] {
            return mergeDictionariesIterative(target: targetDict, source: sourceDict, options: options)
        }
        return merge(target: target, source: source, options: options)
    }

    private struct DictionaryMergeFrame {
        var target: [AnyHashable: Any]
        let sourceItems: [(AnyHashable, Any)]
        var index: Int
        let sourceIsOverflow: Bool
        let sourceMax: Int?
        var overflowMax: Int?
        var pendingKey: AnyHashable?
    }

    private static func makeDictionaryMergeFrame(
        target: [AnyHashable: Any],
        source: [AnyHashable: Any]
    ) -> DictionaryMergeFrame {
        let targetIsOverflow = Utils.isOverflow(target)
        let sourceIsOverflow = Utils.isOverflow(source)
        let sourceMax = Utils.overflowMaxIndex(source)
        let overflowMax: Int? = {
            if targetIsOverflow { return Utils.overflowMaxIndex(target) ?? -1 }
            if sourceIsOverflow { return -1 }
            return nil
        }()
        let items = source.compactMap { (key: AnyHashable, value: Any) -> (AnyHashable, Any)? in
            Utils.isOverflowKey(key) ? nil : (key, value)
        }
        return DictionaryMergeFrame(
            target: target,
            sourceItems: items,
            index: 0,
            sourceIsOverflow: sourceIsOverflow,
            sourceMax: sourceMax,
            overflowMax: overflowMax,
            pendingKey: nil
        )
    }

    private static func mergeDictionariesIterative(
        target: [AnyHashable: Any],
        source: [AnyHashable: Any],
        options: DecodeOptions
    ) -> [AnyHashable: Any] {
        var stack: [DictionaryMergeFrame] = [makeDictionaryMergeFrame(target: target, source: source)]
        var completed: [AnyHashable: Any]?

        while var frame = stack.popLast() {
            if let pendingKey = frame.pendingKey, let childResult = completed {
                frame.target[pendingKey] = childResult
                frame.pendingKey = nil
                completed = nil
            }

            if frame.index < frame.sourceItems.count {
                let (key, value) = frame.sourceItems[frame.index]
                frame.index += 1

                if let existingValue = frame.target[key] {
                    if let existingDict = existingValue as? [AnyHashable: Any],
                        let valueDict = value as? [AnyHashable: Any]
                    {
                        frame.pendingKey = key
                        stack.append(frame)
                        stack.append(
                            makeDictionaryMergeFrame(target: existingDict, source: valueDict)
                        )
                        continue
                    }
                    frame.target[key] = mergeValues(target: existingValue, source: value, options: options)
                } else {
                    frame.target[key] = value
                }

                if let idx = Utils.intIndex(key), let current = frame.overflowMax, idx > current {
                    frame.overflowMax = idx
                }

                stack.append(frame)
                continue
            }

            if frame.sourceIsOverflow {
                if let sourceMax = frame.sourceMax, sourceMax > (frame.overflowMax ?? -1) {
                    frame.overflowMax = sourceMax
                }
            }
            if let maxIndex = frame.overflowMax {
                Utils.setOverflowMaxIndex(&frame.target, maxIndex)
            }
            completed = frame.target
        }

        return completed ?? target
    }
}

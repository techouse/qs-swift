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
    /// - Throws: `DecodeError.listLimitExceeded` when strict limit enforcement rejects growth.
    @usableFromInline
    static func merge(
        target: Any?,
        source: Any?,
        options: DecodeOptions = DecodeOptions()
    ) throws -> Any? {
        guard let source = source else { return target }
        if isFalsyMergeSource(source) { return target }

        if let tArr = target as? [Any?], let sDict = source as? [AnyHashable: Any] {
            var tDict: [AnyHashable: Any] = [:]

            for (idx, element) in tArr.enumerated() where !(element is Undefined) {
                tDict[idx] = element ?? NSNull()
            }

            return try mergeDictionariesIterative(
                target: tDict,
                source: sDict,
                options: options
            )
        }

        if let tDict = target as? [AnyHashable: Any], let sArr = source as? [Any?] {
            var sDict: [AnyHashable: Any] = [:]
            for (idx, element) in sArr.enumerated() where !(element is Undefined) {
                sDict[idx] = element ?? NSNull()
            }
            return try mergeDictionariesIterative(
                target: tDict,
                source: sDict,
                options: options
            )
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
                if let seq = asSequence(source) {
                    var mutableTarget: [Int: Any?] = [:]

                    for (index, value) in targetArray.enumerated() {
                        mutableTarget[index] = value
                    }

                    var logicalLength = targetArray.count
                    for (index, item) in seq.enumerated() where !(item is Undefined) {
                        if let existing = mutableTarget[index], !(existing is Undefined) {
                            let existingIsContainer =
                                existing is [Any] || existing is [AnyHashable: Any]
                            let itemIsContainer =
                                item is [Any] || item is [AnyHashable: Any]
                            if existingIsContainer, itemIsContainer {
                                mutableTarget[index] = try mergeValues(
                                    target: existing,
                                    source: item,
                                    options: options
                                )
                            } else {
                                mutableTarget[logicalLength] = item
                                logicalLength += 1
                            }
                        } else {
                            mutableTarget[index] = item
                            if index >= logicalLength {
                                logicalLength = index + 1
                            }
                        }
                    }

                    let merged = (0..<logicalLength).map {
                        mutableTarget[$0] ?? Undefined.instance
                    }
                    if !options.parseLists
                        && merged.contains(where: { $0 is Undefined })
                    {
                        // Preserve original element order by iterating indices in ascending order.
                        // Drop both `nil` and `Undefined` entries to match prior semantics.
                        let pruned: [Any] = merged.compactMap { value in
                            guard let value else { return nil }
                            return (value is Undefined) ? nil : value
                        }
                        return try enforceListLimit(pruned, options: options)
                    }

                    return try enforceListLimit(merged, options: options)
                } else {
                    // Source is not a sequence and target cannot be a Set/OrderedSet here.
                    return try enforceListLimit(targetArray + [source], options: options)
                }
            } else if let targetDict = target as? [AnyHashable: Any] {
                if Utils.isOverflow(targetDict) {
                    if options.throwOnLimitExceeded {
                        throw DecodeError.listLimitExceeded(limit: options.listLimit)
                    }
                    var overflow = targetDict
                    var maxIndex = Utils.overflowMaxIndex(overflow) ?? -1

                    if let seq = asSequence(source) {
                        let items = seq.filter { !($0 is Undefined) }
                        for (offset, item) in items.enumerated() {
                            guard let nextIndex = Utils.nextOverflowIndex(after: maxIndex) else {
                                var values: [Any?] = [Utils.removingOverflowMetadata(from: overflow)]
                                values.append(contentsOf: items[offset...].map { $0 as Any? })
                                return try enforceListLimit(values, options: options)
                            }
                            maxIndex = nextIndex
                            overflow[maxIndex] = item
                        }
                    } else if !(source is Undefined) {
                        guard let nextIndex = Utils.nextOverflowIndex(after: maxIndex) else {
                            let values: [Any?] = [
                                Utils.removingOverflowMetadata(from: overflow),
                                source,
                            ]
                            return try enforceListLimit(values, options: options)
                        }
                        maxIndex = nextIndex
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
                } else if !isFalsyMergeSource(source) {
                    if options.strictMerge {
                        return [targetDict, source]
                    }
                    let key = String(describing: source)
                    if !key.isEmpty { mutableTarget[key] = true }
                }

                return mutableTarget
            } else {
                if let seq = asSequence(source) {
                    var result: [Any?] = [target]  // preserve nil at index 0
                    result.append(contentsOf: seq)
                    if result.count > options.listLimit {
                        return try enforceListLimit(result, options: options)
                    }
                    return result
                }
                // qs returns the scalar pair directly here. Limit enforcement
                // applies to array/primitive directions, while scalar collisions
                // inside an overflow map remain a nested two-element value.
                return [target as Any?, source as Any?]
            }
        }

        if target == nil || !(target is [AnyHashable: Any]) {
            if let sourceDict = source as? [AnyHashable: Any], Utils.isOverflow(sourceDict) {
                if options.throwOnLimitExceeded {
                    throw DecodeError.listLimitExceeded(limit: options.listLimit)
                }
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
                        guard let shiftedIndex = Utils.nextOverflowIndex(after: idx) else {
                            return try merge(
                                target: target,
                                source: Utils.removingOverflowMetadata(from: sourceDict),
                                options: options
                            )
                        }
                        result[shiftedIndex] = value
                    } else {
                        result[key] = value
                    }
                }

                guard let newMax = Utils.nextOverflowIndex(
                    after: Utils.overflowMaxIndex(sourceDict) ?? -1
                ) else {
                    return try merge(
                        target: target,
                        source: Utils.removingOverflowMetadata(from: sourceDict),
                        options: options
                    )
                }
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

                return try enforceListLimit(mutableTarget, options: options)
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
            return try mergeDictionariesIterative(
                target: mergeTarget,
                source: sourceDict,
                options: options
            )
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
    private static func isFalsyMergeSource(_ value: Any) -> Bool {
        if value is Undefined || value is NSNull { return true }
        if let string = value as? String { return string.isEmpty }
        if let bool = value as? Bool { return !bool }
        if let number = value as? NSNumber { return number.doubleValue == 0 }
        return false
    }

    @inline(__always)
    private static func mergeValues(
        target: Any?,
        source: Any?,
        options: DecodeOptions
    ) throws -> Any? {
        if let targetDict = target as? [AnyHashable: Any], let sourceDict = source as? [AnyHashable: Any] {
            return try mergeDictionariesIterative(
                target: targetDict,
                source: sourceDict,
                options: options
            )
        }
        return try merge(target: target, source: source, options: options)
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
    ) throws -> [AnyHashable: Any] {
        if options.throwOnLimitExceeded,
            Utils.isOverflow(target) || Utils.isOverflow(source)
        {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }

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
                let targetKey = matchingDictionaryKey(for: key, in: frame.target)
                frame.index += 1

                if let existingValue = frame.target[targetKey] {
                    if let existingDict = existingValue as? [AnyHashable: Any],
                        let valueDict = value as? [AnyHashable: Any]
                    {
                        if options.throwOnLimitExceeded,
                            Utils.isOverflow(existingDict) || Utils.isOverflow(valueDict)
                        {
                            throw DecodeError.listLimitExceeded(limit: options.listLimit)
                        }
                        frame.pendingKey = targetKey
                        stack.append(frame)
                        stack.append(
                            makeDictionaryMergeFrame(target: existingDict, source: valueDict)
                        )
                        continue
                    }
                    frame.target[targetKey] = try mergeValues(
                        target: existingValue,
                        source: value,
                        options: options
                    )
                } else {
                    frame.target[targetKey] = value
                }

                if let idx = Utils.intIndex(targetKey), let current = frame.overflowMax, idx > current {
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

    /// JavaScript object keys do not distinguish an integer index from its canonical string form.
    private static func matchingDictionaryKey(
        for key: AnyHashable,
        in target: [AnyHashable: Any]
    ) -> AnyHashable {
        if target[key] != nil { return key }

        if let index = Utils.intIndex(key) {
            let stringKey = AnyHashable(String(index))
            if target[stringKey] != nil { return stringKey }
        } else if let stringKey = key.base as? String,
            let index = Int(stringKey),
            index >= 0,
            String(index) == stringKey
        {
            let integerKey = AnyHashable(index)
            if target[integerKey] != nil { return integerKey }
        }

        return key
    }
}

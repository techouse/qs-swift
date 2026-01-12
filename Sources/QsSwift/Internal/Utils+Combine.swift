import Foundation

extension Utils {
    /// Combines two objects into an array. If either object is an Array, its elements are added to the array.
    /// If either object is a primitive, it is added as a single element.
    ///
    /// - Parameters:
    ///   - first: The first object to combine.
    ///   - second: The second object to combine.
    /// - Returns: An array containing the combined elements.
    @usableFromInline
    static func combine<T>(_ first: Any?, _ second: Any?) -> [T] {
        var result: [T] = []

        if let arrayA = first as? [T] {
            result.append(contentsOf: arrayA)
        } else if let itemA = first as? T {
            result.append(itemA)
        }

        if let arrayB = second as? [T] {
            result.append(contentsOf: arrayB)
        } else if let itemB = second as? T {
            result.append(itemB)
        }

        return result
    }

    /// Combines two objects while honoring list limits; may return an overflow map.
    /// - Returns: `[Any?]` when within limit, or `[AnyHashable: Any]` when exceeded.
    @usableFromInline
    static func combine(_ first: Any?, _ second: Any?, listLimit: Int) -> Any {
        if let dict = first as? [AnyHashable: Any], isOverflow(dict) {
            return appendOverflow(dict, value: second)
        }

        var result: [Any?] = []
        appendCombineValue(first, into: &result)
        appendCombineValue(second, into: &result)

        guard listLimit >= 0, result.count > listLimit else {
            return result
        }

        return arrayToOverflowObject(result)
    }

    private static func appendCombineValue(_ value: Any?, into array: inout [Any?]) {
        if let arrOpt = value as? [Any?] {
            array.append(contentsOf: arrOpt)
        } else if let arr = value as? [Any] {
            array.append(contentsOf: arr.map(Optional.some))
        } else if let value = value {
            array.append(value)
        }
    }

    private static func arrayToOverflowObject(_ array: [Any?]) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [:]
        dict.reserveCapacity(array.count + 1)
        for (index, value) in array.enumerated() {
            dict[index] = value ?? NSNull()
        }
        return markOverflow(dict, maxIndex: array.count - 1)
    }

    private static func appendOverflow(
        _ dict: [AnyHashable: Any],
        value: Any?
    ) -> [AnyHashable: Any] {
        guard let value = value else { return dict }
        var copy = dict
        let currentMax = overflowMaxIndex(copy) ?? -1
        let nextIndex = currentMax + 1
        copy[nextIndex] = value
        setOverflowMaxIndex(&copy, nextIndex)
        return copy
    }
}

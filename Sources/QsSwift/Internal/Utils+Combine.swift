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

    /// Combines two objects while honoring list limits; may throw or return an overflow map.
    /// - Returns: `[Any?]` when within limit, or `[AnyHashable: Any]` when exceeded.
    @usableFromInline
    static func combine(_ first: Any?, _ second: Any?, options: DecodeOptions) throws -> Any {
        if let dict = first as? [AnyHashable: Any], isOverflow(dict) {
            if options.throwOnLimitExceeded {
                throw DecodeError.listLimitExceeded(limit: options.listLimit)
            }
            return appendOverflow(dict, value: second)
        }

        var result: [Any?] = []
        appendCombineValue(first, into: &result)
        appendCombineValue(second, into: &result)

        return try enforceListLimit(result, options: options)
    }

    /// Keeps an in-limit list, throws in strict mode, or converts every value to an overflow map.
    @usableFromInline
    static func enforceListLimit<Element>(_ values: [Element], options: DecodeOptions) throws -> Any {
        guard values.count > options.listLimit else { return values }
        if options.throwOnLimitExceeded {
            throw DecodeError.listLimitExceeded(limit: options.listLimit)
        }
        return arrayToOverflowObject(values.map { $0 as Any? })
    }

    private static func appendCombineValue(_ value: Any?, into array: inout [Any?]) {
        if let arrOpt = value as? [Any?] {
            array.append(contentsOf: arrOpt)
        } else if let arr = value as? [Any] {
            array.reserveCapacity(array.count + arr.count)
            for element in arr {
                array.append(element)
            }
        } else if let value = value {
            array.append(value)
        }
    }

    private static func arrayToOverflowObject(_ array: [Any?]) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [:]
        dict.reserveCapacity(array.count + 1)
        for (index, value) in array.enumerated() where !(value is Undefined) {
            dict[index] = value ?? NSNull()
        }
        return markOverflow(dict, maxIndex: array.count - 1)
    }

    private static func appendOverflow(
        _ dict: [AnyHashable: Any],
        value: Any?
    ) -> [AnyHashable: Any] {
        var copy = dict
        var maxIndex = overflowMaxIndex(copy) ?? -1
        maxIndex += 1
        copy[maxIndex] = value ?? NSNull()
        setOverflowMaxIndex(&copy, maxIndex)
        return copy
    }
}

import Foundation

extension Utils {
    /// Combines two objects into an array. If either object is an Array, its elements are added to the array.
    /// If either object is a primitive, it is added as a single element.
    ///
    /// - Parameters:
    ///   - a: The first object to combine.
    ///   - b: The second object to combine.
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
}

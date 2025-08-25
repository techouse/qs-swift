import Foundation

extension Utils {
    /// Applies a function to a value or each element in an Array. If the value is an Array,
    /// the function is applied to each element. If the value is a single item, the function is applied directly.
    ///
    /// - Parameters:
    ///   - value: The value or Array to apply the function to.
    ///   - fn: The function to apply.
    /// - Returns: The result of applying the function, or nil if the input is nil.
    static func apply<T>(_ value: Any?, _ fn: (T) -> T) -> Any? {
        if let array = value as? [T] {
            return array.map(fn)
        } else if let item = value as? T {
            return fn(item)
        }
        return nil
    }
}

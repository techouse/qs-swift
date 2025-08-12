import Foundation

// MARK: - Dictionary convenience

extension Dictionary where Key == String, Value == Any? {

    /// Returns a new `[String: Any]` by **bridging top-level optionals**:
    /// any `nil` value becomes `NSNull()`, everything else is left as-is.
    ///
    /// - Important:
    ///   - This is **shallow**: it does not recurse into nested dictionaries/arrays.
    ///     Use your existing deep bridge (`Utils.deepBridgeToAnyIterative`) when you
    ///     need to normalize an entire object graph.
    ///   - `Dictionary` does not guarantee stable key order; if ordering matters,
    ///     prefer `OrderedDictionary` at the call site.
    @inlinable
    func bridgedOptionalsToAny() -> [String: Any] {
        mapValues { $0 ?? NSNull() }
    }

    /// Deprecated: use `bridgedOptionalsToAny()` for a clearer name.
    @available(*, deprecated, message: "Use bridgedOptionalsToAny()")
    @inlinable
    func mapValuesToAny() -> [String: Any] {
        bridgedOptionalsToAny()
    }
}

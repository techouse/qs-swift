import Foundation

/// Marker protocol for types that can restrict or transform what gets encoded.
///
/// Conformers are used by `EncodeOptions.filter` to:
/// - include/exclude specific keys or indices,
/// - transform values prior to encoding,
/// - or both.
///
/// Two built-ins are provided:
/// - `FunctionFilter` — run a closure for each key/value
/// - `IterableFilter` — whitelist specific keys/indices
public protocol Filter {}

/// A filter backed by a closure that can transform or drop values.
///
/// The closure receives the **flattened** key path (e.g. `"a[b][0]"`) and the
/// raw value, and should return either:
/// - a transformed value (encode it),
/// - `nil` to omit the key entirely,
/// - or leave the value unchanged.
///
/// ### Examples
/// Omit keys that start with an underscore:
/// ```swift
/// let f = FunctionFilter { key, value in
///     key.hasPrefix("_") ? nil : value
/// }
/// ```
/// Double just the `"count"` value:
/// ```swift
/// let f = FunctionFilter { key, value in
///     key == "count", let n = value as? Int ? (n * 2) : value
/// }
/// ```
public struct FunctionFilter: Filter, CustomStringConvertible {
    /// The transformation function. Returning `nil` drops the key.
    public let function: (String, Any?) -> Any?

    public init(_ function: @escaping (String, Any?) -> Any?) {
        self.function = function
    }

    public var description: String { "FunctionFilter(<closure>)" }
}

/// A filter that whitelists a fixed set of keys/indices.
///
/// - For dictionaries, include only the listed string keys.
/// - For arrays, include only the listed integer indices.
/// - Mixed lists (e.g. `["a", 0, 2]`) allow both in a single pass.
///
/// This does **not** transform values; it only selects which entries are visited.
///
/// ### Examples
/// ```swift
/// // Keep only "a" and "e"
/// let f1 = IterableFilter.keys("a", "e")
///
/// // Keep only array indices 0 and 2
/// let f2 = IterableFilter.indices(0, 2)
///
/// // Mixed: keep "a" and indices 0, 2
/// let f3 = IterableFilter.mixed("a", 0, 2)
/// ```
public struct IterableFilter: Filter, CustomStringConvertible {
    /// The allowlist of keys/indices (`String` keys and/or `Int` indices).
    public let iterable: [Any]

    public init<T: Sequence>(_ iterable: T) {
        self.iterable = Array(iterable)
    }

    public init(_ array: [Any]) {
        self.iterable = array
    }

    public var description: String { "IterableFilter(\(iterable))" }
}

// MARK: - Convenience factories

extension FunctionFilter {
    /// Exclude keys for which the predicate returns `true`.
    public static func excluding(_ shouldExclude: @escaping (String) -> Bool) -> FunctionFilter {
        FunctionFilter { key, value in
            shouldExclude(key) ? nil : value
        }
    }

    /// Include keys for which the predicate returns `true`.
    public static func including(_ shouldInclude: @escaping (String) -> Bool) -> FunctionFilter {
        FunctionFilter { key, value in
            shouldInclude(key) ? value : nil
        }
    }

    /// Transform values for specific keys; other keys pass through unchanged.
    public static func transforming(_ keyTransforms: [String: (Any?) -> Any?]) -> FunctionFilter {
        FunctionFilter { key, value in
            if let transform = keyTransforms[key] { return transform(value) }
            return value
        }
    }
}

extension IterableFilter {
    /// Convenience: include only the specified string keys.
    public static func keys(_ keys: String...) -> IterableFilter { IterableFilter(keys) }

    /// Convenience: include only the specified integer indices.
    public static func indices(_ indices: Int...) -> IterableFilter { IterableFilter(indices) }

    /// Convenience: include a mixed list of keys and indices.
    public static func mixed(_ items: Any...) -> IterableFilter { IterableFilter(items) }
}

import Foundation

/// A sentinel value that means “key is *absent* (undefined)”, as opposed to:
/// - `nil` / `NSNull()` → “key is present, with a null/empty value”
///
/// `Undefined` is used by the encoder (e.g. via `FunctionFilter`) to **omit** a key entirely
/// during serialization. It’s distinct from empty strings, `nil`, and `NSNull`, all of which
/// still render a key (subject to `skipNulls` / `strictNullHandling`).
///
/// You can construct it directly (`Undefined()`) or use the canonical singleton
/// (`Undefined.instance`). All instances are equal and interchangeable.
@frozen
public struct Undefined: Equatable, Hashable, Sendable {

    /// Public initializer so clients can write `Undefined()`.
    @inlinable
    public init() {}

    /// Canonical singleton, for convenience.
    public static let instance = Undefined()
}

// MARK: - CustomStringConvertible / Debug

extension Undefined: CustomStringConvertible, CustomDebugStringConvertible {
    /// Human-readable representation, useful in logs and tests.
    public var description: String { "Undefined" }
    public var debugDescription: String { description }
}

// MARK: - Convenience

extension Undefined {
    /// Callable-type sugar: `Undefined()` or `Undefined.callAsFunction()` both return a value.
    /// Mirrors Kotlin’s companion `invoke`-style ergonomics.
    @inlinable
    public static func callAsFunction() -> Undefined { .instance }
}

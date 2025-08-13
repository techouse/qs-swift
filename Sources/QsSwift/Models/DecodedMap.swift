/// A tiny `Sendable` wrapper around a decoded `[String: Any]`.
///
/// - Why this exists:
///   Swift’s plain `[String: Any]` is **not** `Sendable`, which makes it awkward to
///   return from background work in strict-concurrency code. `DecodedMap` lets us
///   cross executor/queue boundaries without sprinkling `@preconcurrency` or
///   weakening concurrency checks elsewhere.
///
/// - Safety:
///   This type is marked `@unchecked Sendable` because it does **not** enforce
///   deep thread safety of the contained values (they can include reference types).
///   Treat the wrapped dictionary as **logically immutable** once produced—don’t
///   mutate it across threads.
///
/// - Usage:
///   * Prefer returning `DecodedMap` from async decode APIs that hop off the main
///     actor (e.g. `decodeAsync` / `decodeAsyncOnMain`).
///   * If you need the raw dictionary, read `value` immediately on your target
///     executor and keep it confined there.
///
/// - Example:
///   ```swift
///   let map = try await Qs.decodeAsync("a=b").value   // use on current actor
///   ```
public struct DecodedMap: @unchecked Sendable {
    /// The decoded key–value pairs. Treat as read-only across threads.
    public let value: [String: Any]

    @inlinable
    public init(_ v: [String: Any]) { self.value = v }
}

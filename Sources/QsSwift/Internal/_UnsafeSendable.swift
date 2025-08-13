/// A tiny, **unsafe** box used to hop non-`Sendable` values across concurrency boundaries.
///
/// Why this exists:
/// - Some APIs (e.g. `withCheckedContinuation`, GCD) require `@Sendable` closures.
/// - Capturing non-`Sendable` values (like `[String: Any]`, `DecodeOptions`, etc.) in those
///   closures trips the strict concurrency checker.
/// - `_UnsafeSendable` provides an explicit escape hatch when you *know* the captured value
///   won’t be concurrently mutated or observed, and you only need a one-shot handoff to a
///   background queue/thread.
///
/// WARNING: Safety contract (you must uphold this):
/// - Treat the wrapped `value` as **immutable** while/after handing it off.
/// - Do **not** share the same reference to mutable reference types across threads.
/// - Prefer making your types conform to `Sendable` instead, or using actors/isolated APIs.
/// - This is intended for short-lived bridging in internal implementation details (e.g.
///   boxing arguments before dispatching work to a background queue).
///
/// Example:
/// ```swift
/// try await withCheckedThrowingContinuation { cont in
///     let inputBox = _UnsafeSendable(input)           // non-Sendable
///     let optsBox  = _UnsafeSendable(options)         // non-Sendable
///     DispatchQueue.global(qos: .userInitiated).async {
///         do { cont.resume(returning: try work(inputBox.value, optsBox.value)) }
///         catch { cont.resume(throwing: error) }
///     }
/// }
/// ```
///
/// Notes:
/// - Marked `@unchecked Sendable` because the compiler cannot prove safety.
/// - Marked `@frozen` to lock layout/ABI if used across module boundaries; do not add
///   stored properties later.
///
/// Prefer safer alternatives whenever possible; use this as a last resort.
@frozen public struct _UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) { value = v }
}

import Foundation

/// Tiny wrapper to carry an Objective-C block through places that require `@Sendable`.
///
/// Why this exists:
/// - Obj-C blocks are not `Sendable`, so capturing them directly in `@Sendable`
///   Swift closures (e.g. when hopping threads) triggers concurrency warnings.
/// - This box is a reference type annotated `@unchecked Sendable`, letting us
///   move the block across threads without compiler complaints.
///
/// Safety notes:
/// - The wrapped block is treated as **immutable**: we only read it after init,
///   never mutate it. That makes the `@unchecked` annotation a sound escape hatch.
/// - If the block captures non-thread-safe state, you still need to ensure
///   correct synchronization in the block itself (like any cross-thread callback).
///
/// Usage:
/// ```swift
/// let box = _BlockBox(myObjCBlock)
/// DispatchQueue.global().async {
///   // Safe to call on any thread
///   box.block(arg1, arg2)
/// }
/// ```
///
/// Implementation detail:
/// - `final` for minimal dispatch and to avoid subclassing surprises.
/// - `internal` because it’s a helper used only inside the bridge layer.
internal final class _BlockBox<T>: @unchecked Sendable {
    let block: T
    init(_ block: T) { self.block = block }
}

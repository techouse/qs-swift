#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation

    /// A tiny generic box that lets you smuggle a **non-Sendable** value through an
    /// `@Sendable` closure boundary without compiler warnings.
    ///
    /// Why this exists:
    /// - Swift’s concurrency model requires values captured by `@Sendable` closures to
    ///   conform to `Sendable`.
    /// - Many Foundation/ObjC types (and user types) aren’t `Sendable`.
    /// - By wrapping the value in this reference type annotated `@unchecked Sendable`,
    ///   we can hop threads (e.g. in async helpers) without sprinkling `@preconcurrency`
    ///   or loosening constraints elsewhere.
    ///
    /// Safety notes:
    /// - The box is **immutable**: its `value` is a `let` constant. We only read it
    ///   after initialization. This makes `@unchecked Sendable` a reasonable escape hatch.
    /// - This does **not** make the underlying value thread-safe. If `value` refers to
    ///   a type with internal mutability, it’s still your responsibility to ensure
    ///   correct synchronization when you use it on another thread.
    /// - The box holds a **strong** reference to `value`. Be mindful of reference
    ///   cycles or large graphs captured for long-lived tasks.
    ///
    /// Typical usage (in this codebase):
    /// ```swift
    /// let objBox = _AnySendableBox(object)        // object may be non-Sendable
    /// let optBox = _AnySendableBox(options)       // options may be non-Sendable
    /// DispatchQueue.global(qos: .userInitiated).async {
    ///     // Safe to read inside @Sendable closure
    ///     var err: NSError?
    ///     let s = QsBridge.encode(objBox.value, options: optBox.value, error: &err)
    ///     completion(s, err)
    /// }
    /// ```
    ///
    /// Scope:
    /// - `internal` as it’s a bridge-layer utility.
    /// - `final` to prevent subclassing and keep semantics tight.
    internal final class _AnySendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

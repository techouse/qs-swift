import Foundation

/// Identity-based weak key wrapper for use in weak maps/sets.
///
/// - Equality: `true` **only** when both referents are still alive and identical (`===`).
///             If either side has been deallocated, equality is `false`.
/// - Hashing: a stable hash captured from the referent’s `ObjectIdentifier` at construction,
///            so the key remains usable in hash tables after the referent is deallocated.
///
/// This design intentionally avoids “reviving” equality after deallocation (two collected
/// wrappers do **not** compare equal), which prevents distinct keys collapsing later.
internal final class WeakWrapper<T: AnyObject> {
    /// Weak reference to the wrapped object (may become `nil` at any time).
    private weak var weakRef: T?

    /// Hash derived from the referent’s identity at construction time.
    /// Remains stable even after the referent is deallocated.
    private let identityHash: Int

    /// Initializes a new wrapper around `value`.
    init(_ value: T) {
        self.weakRef = value
        self.identityHash = ObjectIdentifier(value).hashValue
    }

    /// Returns the referent if still alive; otherwise `nil`.
    /// Note: deallocation can happen at any time due to ARC.
    func get() -> T? {
        return weakRef
    }
}

extension WeakWrapper: Equatable {
    /// Returns `true` iff both referents are alive **and** `===`.
    static func == (lhs: WeakWrapper<T>, rhs: WeakWrapper<T>) -> Bool {
        // First check if they're the same wrapper instance.
        if lhs === rhs { return true }

        // Then check if both referents are alive and identical.
        guard let a = lhs.get(), let b = rhs.get() else { return false }
        return a === b
    }
}

extension WeakWrapper: Hashable {
    /// Hashes the captured identity hash (stable post-deallocation).
    func hash(into hasher: inout Hasher) {
        hasher.combine(identityHash)
    }
}

extension WeakWrapper: CustomStringConvertible {
    /// Human-friendly description showing the referent’s type/identity if alive.
    var description: String {
        if let value = get() {
            let className = String(describing: type(of: value))
            let idHash = ObjectIdentifier(value).hashValue
            return "WeakWrapper(\(className)@\(idHash))"
        } else {
            return "WeakWrapper(<deallocated>)"
        }
    }
}

extension WeakWrapper: CustomDebugStringConvertible {
    /// Mirrors `description` for richer debug output in LLDB / logs.
    var debugDescription: String { description }
}

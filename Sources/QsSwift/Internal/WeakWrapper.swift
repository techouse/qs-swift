import Foundation

/// A weak, identity-based key wrapper designed to work correctly with `NSMapTable`.
///
/// Why this exists:
/// - Cycle detection needs to remember **which reference objects** (e.g. `NSArray`/`NSDictionary`)
///   are currently on the recursion path.
/// - `NSMapTable` uses **Objective-C equality** (`isEqual:`/`hash`) — not Swift `Hashable`.
///   If you wrap the same referent multiple times during recursion, lookups must match.
/// - We capture a **stable identity hash** at init (from `ObjectIdentifier`) so the key remains
///   usable even if the referent later deallocates. Equality only returns `true` when **both
///   referents are alive and identical (`===`)**. Two deallocated wrappers do *not* compare equal,
///   which avoids accidental key collapsing after ARC cleanup.
///
/// Notes:
/// - Keys are `WeakWrapper` instances stored in a weak `NSMapTable`, so once the referent
///   deallocates, the map may drop the entry automatically.
/// - This class subclasses `NSObject` to participate in Obj-C hashing/equality for `NSMapTable`.
final class WeakWrapper: NSObject {

    /// Weak reference to the wrapped object (becomes `nil` when the referent is deallocated).
    private weak var weakRef: AnyObject?

    /// Stable hash captured from the referent’s identity at construction time.
    /// Using a captured value keeps `hash` stable even after `weakRef` becomes `nil`.
    private let identityHash: Int

    /// Create a wrapper for a reference-type value.
    ///
    /// - Parameter value: Any reference type (e.g. `NSArray`, `NSDictionary`, custom class).
    init(_ value: AnyObject) {
        self.weakRef = value
        self.identityHash = ObjectIdentifier(value).hashValue
        super.init()
    }

    /// Expose the referent for debugging or optional checks (may be `nil` if deallocated).
    var referent: AnyObject? { weakRef }

    // MARK: - NSObject overrides (used by NSMapTable)

    /// Hash used by `NSMapTable`. Returns the captured identity hash.
    /// Keeping this stable avoids “moving keys” when the referent is collected.
    override var hash: Int { identityHash }

    /// Equality used by `NSMapTable`.
    ///
    /// Semantics:
    /// - `true` iff **both** wrappers still reference live objects and those objects are identical (`===`).
    /// - `false` if either referent has deallocated (we never “revive” equality post-deallocation).
    /// - Fast path: if two wrappers are literally the same instance, they’re equal.
    override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? WeakWrapper else { return false }
        if self === rhs { return true }
        guard let leftRef = weakRef, let rightRef = rhs.weakRef else { return false }
        return leftRef === rightRef
    }

    // MARK: - Debugging

    /// Human-friendly description showing the referent’s type and identity hash when alive.
    override var description: String {
        if let referent = weakRef {
            return "WeakWrapper(\(type(of: referent))@\(identityHash))"
        } else {
            return "WeakWrapper(<deallocated>@\(identityHash))"
        }
    }

    /// Mirror `description` for richer debug output in LLDB / logs.
    override var debugDescription: String { description }
}

#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Objective-C wrapper around `QsSwift.DecodedMap`.
    ///
    /// The Swift core returns a `DecodedMap` (a thin wrapper around `[String: Any]`)
    /// to guarantee dictionary semantics and provide future-proofing. This Obj-C
    /// class mirrors that shape using `NSDictionary` so it can be consumed directly
    /// from Objective-C while still allowing lossless round-trips back to Swift.
    ///
    /// - Thread safety: this type is immutable after initialization. The contained
    ///   `NSDictionary` is expected to be created by the core and not mutated.
    /// - Bridging: use `init(swift:)` to wrap a Swift value, and the `swift`
    ///   computed property to convert back when calling Swift APIs.
    @objc(QsDecodedMap)
    @objcMembers
    public final class DecodedMapObjC: NSObject /*, @unchecked Sendable (opt-in if needed) */ {

        /// The decoded key/value pairs as Foundation types for Objective-C.
        public let value: NSDictionary

        // MARK: - Initializers

        /// Designated initializer.
        /// - Parameter dict: Dictionary produced by the Swift core (bridged to `NSDictionary`).
        public init(_ dict: NSDictionary) {
            self.value = dict
        }

        /// Convenience initializer to wrap a Swift `DecodedMap`.
        public convenience init(swift: QsSwift.DecodedMap) {
            self.init(swift.value as NSDictionary)
        }

        // MARK: - Bridging back to Swift

        /// Convert back to the Swift wrapper.
        ///
        /// Safe because every `DecodedMap` coming from the core is constructed from
        /// a `[String: Any]`. The force-cast reflects that invariant.
        var swift: QsSwift.DecodedMap {
            // Every `DecodedMap` created by the core holds a `[String: Any]`. Use a
            // guarded cast to satisfy SwiftLint (no force_cast) while preserving the
            // original invariant: if this is ever not the expected shape, fail fast.
            guard let dict = value as? [String: Any] else {
                preconditionFailure("QsDecodedMap.value must be a [String: Any] produced by the core")
            }
            return QsSwift.DecodedMap(dict)
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

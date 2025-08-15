#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    @objc extension QsBridge {
        // MARK: - ObjC-friendly: non-throwing decode helpers
        //
        // These mirror the Swift convenience APIs on Qs:
        //   - decodeOrNil:   returns nil only on *error*; nil input decodes to {}
        //   - decodeOrEmpty: returns {} on error (and on nil input)
        //   - decodeOr(_:default:): returns caller-provided default on error
        //
        // All entry points pre-bridge the input with `bridgeInputForDecode(_:)`
        // so common Obj-C shapes (NSString / NSDictionary / NSArray / scalars)
        // become the Swift types expected by the Qs core.

        /// Decode, returning `nil` only if decoding *throws*.
        ///
        /// Behavior:
        /// - `input == nil` → `{}` (empty dictionary), *not* `nil`.
        /// - Errors → `nil`.
        ///
        /// Equivalent to: `decodeOrNil(input, options: nil)`
        @objc(decodeOrNil:)
        public static func decodeOrNil(_ input: Any?) -> NSDictionary? {
            decodeOrNil(input, options: nil)
        }

        /// Decode, returning `nil` only if decoding *throws*.
        ///
        /// Behavior:
        /// - `input == nil` → `{}` (empty dictionary), *not* `nil`.
        /// - Errors → `nil`.
        @objc(decodeOrNil:options:)
        public static func decodeOrNil(_ input: Any?, options: DecodeOptionsObjC?) -> NSDictionary?
        {
            let bridged = bridgeInputForDecode(input)
            let swiftOpts = options?.swift ?? .init()
            if let dict = Qs.decodeOrNil(bridged, options: swiftOpts) {
                return dict as NSDictionary
            }
            return nil
        }

        /// Decode, returning `{}` (empty dictionary) instead of failing.
        ///
        /// Behavior:
        /// - `input == nil` → `{}`.
        /// - Errors → `{}`.
        ///
        /// Equivalent to: `decodeOrEmpty(input, options: nil)`
        @objc(decodeOrEmpty:)
        public static func decodeOrEmpty(_ input: Any?) -> NSDictionary {
            decodeOrEmpty(input, options: nil)
        }

        /// Decode, returning `{}` (empty dictionary) instead of failing.
        ///
        /// Behavior:
        /// - `input == nil` → `{}`.
        /// - Errors → `{}`.
        @objc(decodeOrEmpty:options:)
        public static func decodeOrEmpty(_ input: Any?, options: DecodeOptionsObjC?) -> NSDictionary
        {
            let bridged = bridgeInputForDecode(input)
            let swiftOpts = options?.swift ?? .init()
            let dict = Qs.decodeOrEmpty(bridged, options: swiftOpts)
            return dict as NSDictionary
        }

        /// Decode, returning the provided default dictionary on failure.
        ///
        /// Behavior:
        /// - `input == nil` → `{}` is decoded (no error).
        /// - Errors → `defaultValue`.
        ///
        /// Equivalent to: `decodeOr(input, options: nil, default: defaultValue)`
        @objc(decodeOr:default:)
        public static func decodeOr(_ input: Any?, `default` defaultValue: NSDictionary)
            -> NSDictionary
        {
            decodeOr(input, options: nil, default: defaultValue)
        }

        /// Decode, returning the provided default dictionary on failure.
        ///
        /// Notes:
        /// - `defaultValue` is bridged to `[String: Any]` (non-string keys are stringified)
        ///   to match what the Swift core expects.
        @objc(decodeOr:options:default:)
        public static func decodeOr(
            _ input: Any?,
            options: DecodeOptionsObjC?,
            `default` defaultValue: NSDictionary
        ) -> NSDictionary {
            let bridged = bridgeInputForDecode(input)
            let swiftOpts = options?.swift ?? .init()
            let swiftDefault = (defaultValue as? [String: Any]) ?? [:]
            let dict = Qs.decodeOr(bridged, options: swiftOpts, default: swiftDefault)
            return dict as NSDictionary
        }

        // MARK: - Async decoding (callback-style)
        //
        // Two variants:
        //  - decodeAsyncOnMain: does work on a background queue, but *always* invokes the
        //    completion on the main thread (UI-friendly).
        //  - decodeAsync: does work on a background queue and invokes the completion on the
        //    *same* background queue (lower overhead if you don’t need main-thread hops).
        //
        // We use a tiny `_UnsafeSendable` box to silence Sendable warnings while moving
        // bridged values/options across threads. The bridged values remain immutable
        // within this scope.

        /// Background decode; completion is invoked on the **main** thread.
        @objc(decodeAsyncOnMain:options:completion:)
        public static func decodeAsyncOnMain(
            _ input: Any?,
            options: DecodeOptionsObjC?,
            completion: @escaping @Sendable (NSDictionary?, NSError?) -> Void
        ) {
            let inBox = _UnsafeSendable(bridgeInputForDecode(input) as Any?)
            let optBox = _UnsafeSendable(options?.swift ?? .init())

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let dict = try Qs.decode(inBox.value, options: optBox.value)
                    DispatchQueue.main.async { completion(dict as NSDictionary, nil) }
                } catch {
                    DispatchQueue.main.async { completion(nil, error as NSError) }
                }
            }
        }

        /// Background decode; completion is invoked on the **background** queue used for work.
        @objc(decodeAsync:options:completion:)
        public static func decodeAsync(
            _ input: Any?,
            options: DecodeOptionsObjC?,
            completion: @escaping @Sendable (NSDictionary?, NSError?) -> Void
        ) {
            let inBox = _UnsafeSendable(bridgeInputForDecode(input) as Any?)
            let optBox = _UnsafeSendable(options?.swift ?? .init())

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let dict = try Qs.decode(inBox.value, options: optBox.value)
                    completion(dict as NSDictionary, nil)
                } catch {
                    completion(nil, error as NSError)
                }
            }
        }
    }

    /// Single generic box to silence Sendable warnings when crossing threads.
    /// We never mutate `value` after initialization; the class is marked
    /// `@unchecked Sendable` to avoid unnecessary copies of bridged objects.
    private final class _UnsafeSendable<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

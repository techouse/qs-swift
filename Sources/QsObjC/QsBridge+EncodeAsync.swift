#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation

    @objc extension QsBridge {
        // MARK: - ObjC-friendly async encode wrappers
        //
        // These call through to `QsBridge.encode(_:options:error:)`, but perform the work
        // off the main thread and deliver the result either on the main queue or back on
        // a background queue (see each method). We box captured values to satisfy `@Sendable`
        // without promising thread-safety for Foundation types.

        /// Encodes on a background queue and **invokes the completion on the main queue**.
        ///
        /// - Parameters:
        ///   - object: Any JSON-like object graph (NSDictionary/NSArray/NSString, or Swift).
        ///             Key order is preserved for NSDictionary via OrderedDictionary.
        ///   - options: Objective-C options (may be mutated by you *before* calling; avoid mutating after).
        ///   - completion: Called on the **main queue** with `(result, error)`:
        ///       - `result`: the encoded query string (or `nil` if an error occurred)
        ///       - `error`:  populated with `EncodeErrorInfoObjC` details when non-`nil`
        ///
        /// Notes:
        /// - Under the hood we use the same bridging as the sync `encode`:
        ///   OrderedDictionary for stable key order, cycle preservation (to surface `.cyclicObject`),
        ///   and Undefined bridging.
        @objc(encodeAsyncOnMain:options:completion:)
        public static func encodeAsyncOnMain(
            _ object: Any,
            options: EncodeOptionsObjC?,
            completion: @escaping @Sendable (NSString?, NSError?) -> Void
        ) {
            // Box captures to appease `@Sendable` without changing semantics.
            let objBox = _AnySendableBox(object)
            let optBox = _AnySendableBox(options)

            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSError?
                let s = self.encode(objBox.value, options: optBox.value, error: &err)
                DispatchQueue.main.async { completion(s, err) }
            }
        }

        /// Encodes on a background queue and **invokes the completion on that background queue**.
        ///
        /// This is useful when you’re chaining further background work and don’t want a hop to main.
        ///
        /// - Parameters:
        ///   - object: Any JSON-like object graph (NSDictionary/NSArray/NSString, or Swift).
        ///   - options: Objective-C options (do not mutate after calling).
        ///   - completion: Called on a background queue with `(result, error)`.
        @objc(encodeAsync:options:completion:)
        public static func encodeAsync(
            _ object: Any,
            options: EncodeOptionsObjC?,
            completion: @escaping @Sendable (NSString?, NSError?) -> Void
        ) {
            let objBox = _AnySendableBox(object)
            let optBox = _AnySendableBox(options)

            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSError?
                let s = self.encode(objBox.value, options: optBox.value, error: &err)
                completion(s, err)
            }
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

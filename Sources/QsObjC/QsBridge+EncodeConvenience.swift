#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    @objc extension QsBridge {
        // MARK: - ObjC-friendly encode conveniences
        //
        // These mirror the Swift helpers on Qs:
        //   - encodeOrNil:   returns nil on *error*; nil input is not an error → ""
        //   - encodeOrEmpty: returns "" on error (and on nil input)
        //
        // Input is pre-bridged via `bridgeInputForEncode(_:bridgeUndefined:)` to:
        //   - convert Foundation containers (NSDictionary/NSArray/NSString) to Swift
        //   - produce OrderedDictionary<String, Any> for objects to preserve key order
        //   - map `UndefinedObjC` → Swift `Undefined`
        //   - preserve identity on reference cycles (the encoder will report .cyclicObject)

        /// Encode to a query string, returning `nil` only if encoding *throws*.
        ///
        /// Behavior:
        /// - `data == nil` → returns `""` (empty string), *not* `nil`.
        /// - Errors → `nil`.
        ///
        /// Equivalent to: `encodeOrNil(data, options: nil)`
        @objc(encodeOrNil:)
        public static func encodeOrNil(_ data: Any?) -> NSString? {
            encodeOrNil(data, options: nil)
        }

        /// Encode to a query string, returning `nil` only if encoding *throws*.
        ///
        /// Notes:
        /// - Preserves insertion order of object keys (via OrderedDictionary).
        /// - Preserves reference cycles so the core can surface `.cyclicObject`.
        /// - Bridges `UndefinedObjC` → Swift `Undefined`.
        @objc(encodeOrNil:options:)
        public static func encodeOrNil(_ data: Any?, options: EncodeOptionsObjC?) -> NSString? {
            // Convert + Undefined bridge in one pass while preserving order/cycle semantics.
            let bridged: Any? = data.map { QsBridge.bridgeInputForEncode($0, bridgeUndefined: true) }
            // Encode (nil input is treated as empty → "")
            let encoded = Qs.encodeOrNil(bridged, options: options?.swift ?? .init())
            return encoded.map(NSString.init)
        }

        /// Encode to a query string, returning `""` instead of failing.
        ///
        /// Behavior:
        /// - `data == nil` → returns `""`.
        /// - Errors → returns `""`.
        ///
        /// Equivalent to: `encodeOrEmpty(data, options: nil)`
        @objc(encodeOrEmpty:)
        public static func encodeOrEmpty(_ data: Any?) -> NSString {
            encodeOrEmpty(data, options: nil)
        }

        /// Encode to a query string, returning `""` instead of failing.
        ///
        /// Notes:
        /// - Preserves insertion order of object keys (via OrderedDictionary).
        /// - Preserves reference cycles so the core can surface `.cyclicObject` on throwing variants.
        /// - Bridges `UndefinedObjC` → Swift `Undefined`.
        @objc(encodeOrEmpty:options:)
        public static func encodeOrEmpty(_ data: Any?, options: EncodeOptionsObjC?) -> NSString {
            // Convert + Undefined bridge in one pass while preserving order/cycle semantics.
            let bridged: Any? = data.map { QsBridge.bridgeInputForEncode($0, bridgeUndefined: true) }
            // Encode (nil input is treated as empty → "")
            let encoded = Qs.encodeOrEmpty(bridged, options: options?.swift ?? .init())
            return encoded as NSString
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

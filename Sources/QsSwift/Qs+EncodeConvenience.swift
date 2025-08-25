extension Qs {
    // MARK: - Convenience

    /// Non-throwing convenience: returns `nil` if encoding fails (e.g., cyclic references).
    ///
    /// This simply wraps `try? encode(...)`. Use when failures should be treated as “no output”
    /// rather than test/runtime errors. If you need to distinguish “real empty result” from
    /// “failed to encode”, prefer the throwing `encode` API.
    ///
    /// - Parameters:
    ///   - data: The value to encode.
    ///   - options: Encoder settings.
    /// - Returns: A query string, or `nil` if encoding threw.
    @inlinable
    public static func encodeOrNil(
        _ data: Any?,
        options: EncodeOptions = .init()
    ) -> String? {
        try? encode(data, options: options)
    }

    /// Non-throwing convenience: returns `""` if encoding fails.
    ///
    /// This is equivalent to `(try? encode(...)) ?? ""`. Prefer the throwing `encode` for test code
    /// where failures should surface; use this for UI or logging paths where failure should not crash.
    ///
    /// - Parameters:
    ///   - data: The value to encode.
    ///   - options: Encoder settings.
    /// - Returns: A query string, or `""` if encoding threw.
    @inlinable
    public static func encodeOrEmpty(
        _ data: Any?,
        options: EncodeOptions = .init()
    ) -> String {
        encodeOrNil(data, options: options) ?? ""
    }
}

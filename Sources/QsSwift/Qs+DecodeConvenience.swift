import Foundation

extension Qs {
    // MARK: - Convenience

    /// Decode, but return `nil` instead of throwing on failure.
    ///
    /// - Important: This swallows *all* decoding errors. Prefer `decodeResult`
    ///   if you need to distinguish success/failure without `try/catch`.
    @inlinable
    public static func decodeOrNil(
        _ input: Any?,
        options: DecodeOptions = .init()
    ) -> [String: Any]? {
        try? decode(input, options: options)
    }

    /// Decode, but return `[:]` instead of throwing on failure.
    ///
    /// - Note: Use this for “best effort” parsing where an empty map is an acceptable fallback.
    @inlinable
    public static func decodeOrEmpty(
        _ input: Any?,
        options: DecodeOptions = .init()
    ) -> [String: Any] {
        (try? decode(input, options: options)) ?? [:]
    }

    /// Decode, but return the provided default value on failure.
    ///
    /// - Parameters:
    ///   - defaultValue: The value to return if decoding throws.
    @inlinable
    public static func decodeOr(
        _ input: Any?,
        options: DecodeOptions = .init(),
        default defaultValue: [String: Any]
    ) -> [String: Any] {
        (try? decode(input, options: options)) ?? defaultValue
    }

    /// Decode and capture the result as `Result<[String: Any], Error>`.
    ///
    /// - Useful when you want to propagate or switch on errors without `throws`.
    @inlinable
    public static func decodeResult(
        _ input: Any?,
        options: DecodeOptions = .init()
    ) -> Result<[String: Any], Error> {
        Result { try decode(input, options: options) }
    }

    // MARK: - Async conveniences

    /// Asynchronous decode that guarantees the **return happens on the main actor**.
    ///
    /// - Threading:
    ///   - Work is offloaded to a background queue.
    ///   - The awaited result resumes on the **MainActor**.
    ///
    /// - Concurrency:
    ///   - Arguments are boxed via `_UnsafeSendable` to satisfy strict concurrency rules.
    ///   - Returns a `DecodedMap` (a `Sendable` wrapper around `[String: Any]`).
    ///
    /// - Use this from UI code when you need the result on main (e.g., to update views).
    @MainActor
    public static func decodeAsyncOnMain(
        _ input: Any?,
        options: DecodeOptions = .init(),
        qos: DispatchQoS.QoSClass = .userInitiated
    ) async throws -> DecodedMap {
        try await decodeAsyncBoxed(
            _UnsafeSendable(input),
            options: _UnsafeSendable(options),
            qos: _UnsafeSendable(qos)
        )
    }

    /// Asynchronous decode that returns the **raw** `[String: Any]` value.
    ///
    /// - Threading:
    ///   - Work is done on a background queue; the call does **not** guarantee resumption
    ///     on the MainActor. If you need that, use `decodeAsyncOnMain`.
    ///
    /// - Concurrency:
    ///   - Arguments are boxed via `_UnsafeSendable` before crossing threads.
    ///   - The raw dictionary is returned to the caller’s current executor.
    ///
    /// - Returns: The decoded dictionary.
    public nonisolated static func decodeAsyncValue(
        _ input: Any?,
        options: DecodeOptions = .init(),
        qos: DispatchQoS.QoSClass = .userInitiated
    ) async throws -> [String: Any] {
        let inBox = _UnsafeSendable(input)
        let optBox = _UnsafeSendable(options)
        return try await decodeAsync(inBox.value, options: optBox.value, qos: qos).value
    }
}

/// Indicates the decoding context for a scalar token.
///
/// Use ``DecodeKind/key`` when decoding a key or key segment so the decoder can apply
/// key-specific rules (for example, preserving percent-encoded dots ``%2E``/``%2e``
/// until after key splitting). Use ``DecodeKind/value`` for normal value decoding.
public enum DecodeKind: Int, Sendable, CustomStringConvertible {
    /// The token is a **key** (or a key segment).
    ///
    /// Implementations typically avoid turning ``%2E``/``%2e`` into a literal dot
    /// before key splitting when this kind is used, to match the semantics of the
    /// reference `qs` library.
    case key

    /// The token is a **value**.
    ///
    /// Values are decoded normally (e.g., percent-decoding and charset handling)
    /// without any key-specific protections.
    case value

    /// Human-readable label for logging/debugging.
    public var description: String {
        switch self {
        case .key: return "key"
        case .value: return "value"
        }
    }
}

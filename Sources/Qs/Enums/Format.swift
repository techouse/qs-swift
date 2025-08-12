/// URI component encoding formats (affect how already percent-encoded output is post-processed).
///
/// - `.rfc3986` (default): Leaves `%20` as-is (space stays `%20`).
/// - `.rfc1738`: Rewrites `%20` → `+` to match legacy form-style encoding.
///
/// Note: The formatter operates on *already percent-encoded* text produced by the encoder.
public enum Format: CustomStringConvertible, Sendable {
    /// https://datatracker.ietf.org/doc/html/rfc3986
    case rfc3986

    /// https://datatracker.ietf.org/doc/html/rfc1738
    case rfc1738

    /// Returns a small post-processor that transforms the percent-encoded output
    /// according to the chosen format.
    public var formatter: Formatter {
        switch self {
        case .rfc3986:
            // No transformation
            return Formatter { $0 }
        case .rfc1738:
            // Replace %20 with +
            return Formatter { $0.replacingOccurrences(of: "%20", with: "+") }
        }
    }

    /// Human-readable label for logs/debugging.
    public var description: String {
        switch self {
        case .rfc3986: return "rfc3986"
        case .rfc1738: return "rfc1738"
        }
    }
}

// MARK: - Formatter

/// A tiny post-processor applied to the encoder’s *percent-encoded* output.
/// Used to implement RFC3986/RFC1738 differences (e.g., `%20` → `+`).
@frozen
public struct Formatter: Sendable {
    /// Apply the transformation.
    public let apply: @Sendable (_ input: String) -> String

    /// Create a new formatter with the given transformation.
    @inlinable
    public init(apply: @escaping @Sendable (_ input: String) -> String) {
        self.apply = apply
    }
}

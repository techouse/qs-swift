/// A function that produces the full key for a list element given the current path.
///
/// - Parameters:
///   - prefix: The key path built so far (e.g., `"a"`, `"a[b]"`).
///   - key: The list element key for formats that need it (e.g., `"0"` for `.indices`);
///          ignored for formats that don’t encode an index in the key.
/// - Returns: The full key for the element (e.g., `"a[]"`, `"a[0]"`, or `"a"`).
public typealias ListFormatGenerator = @Sendable (_ prefix: String, _ key: String?) -> String

/// List serialization strategies used by the encoder when emitting arrays.
public enum ListFormat: CustomStringConvertible, Sendable {
    /// `foo[]=123&foo[]=456&foo[]=789`
    case brackets

    /// `foo=123,456,789`
    ///
    /// Use with care: this format serializes multiple values into a single scalar parameter.
    /// Round-tripping is best-effort and may require `EncodeOptions.commaRoundTrip = true`
    /// to tag single-element arrays as `foo[]=x`.
    case comma

    /// `foo=123&foo=456&foo=789`
    case repeatKey

    /// `foo[0]=123&foo[1]=456&foo[2]=789`
    case indices

    /// Returns a generator that forms the element key for this list format.
    ///
    /// Examples (for `prefix == "foo"`):
    /// - `.brackets` → `"foo[]"`
    /// - `.repeatKey` / `.comma` → `"foo"`
    /// - `.indices` with `key == "0"` → `"foo[0]"`
    @inlinable
    public var generator: ListFormatGenerator {
        switch self {
        case .brackets:
            return { prefix, _ in "\(prefix)[]" }
        case .comma:
            return { prefix, _ in prefix }
        case .repeatKey:
            return { prefix, _ in prefix }
        case .indices:
            return { prefix, key in "\(prefix)[\(key ?? "")]" }
        }
    }

    /// Human-readable label for logs/debugging.
    public var description: String {
        switch self {
        case .brackets: return "brackets"
        case .comma: return "comma"
        case .repeatKey: return "repeat"
        case .indices: return "indices"
        }
    }
}

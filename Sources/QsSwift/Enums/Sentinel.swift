import Foundation

/// Charset “sentinel” markers used by Rails-style forms to signal the request’s encoding.
///
/// Some forms include a leading `utf8=...` pair so servers can infer whether the payload
/// is UTF-8 or ISO-8859-1 (latin-1). Qs uses these sentinels when
/// `DecodeOptions.charsetSentinel == true` or `EncodeOptions.charsetSentinel == true`.
///
/// Usage:
/// - **Decoding**: If a part equals `Sentinel.charset.encoded` (✓ in UTF-8), treat input as UTF-8.
///   If it equals `Sentinel.iso.encoded` (numeric entity of ✓), treat input as ISO-8859-1.
///   The sentinel pair itself is omitted from results.
/// - **Encoding**: When enabled, Qs prefixes the output with the appropriate sentinel.
///
/// Notes:
/// - `value` returns the *literal* (unencoded) mark: `"✓"` or `"&#10003;"`.
/// - `encoded`/`description` return the full `key=value` pair used on the wire (e.g. `utf8=%E2%9C%93`).
public enum Sentinel: CustomStringConvertible, Sendable {
    /// Numeric-entity checkmark: browsers emit this when the page/request uses ISO-8859-1.
    case iso

    /// Percent-encoded UTF-8 checkmark: indicates the request is UTF-8.
    case charset

    // MARK: Encoded constants (cached once)

    /// Full percent-encoded pair for a UTF-8 checkmark: `utf8=%E2%9C%93`.
    public static let charsetString = "utf8=%E2%9C%93"  // encodeURIComponent("✓")

    /// Full percent-encoded pair for the numeric-entity checkmark: `utf8=%26%2310003%3B`.
    public static let isoString = "utf8=%26%2310003%3B"  // encodeURIComponent("&#10003;")

    // MARK: Derived values

    /// The literal (unencoded) sentinel mark.
    /// - `.charset` → `"✓"`
    /// - `.iso`     → `"&#10003;"`
    @inlinable
    public var value: String {
        switch self {
        case .iso: return "&#10003;"
        case .charset: return "✓"
        }
    }

    /// The full percent-encoded `key=value` pair (what actually appears in a query string).
    @inlinable
    public var encoded: String {
        switch self {
        case .charset: return Self.charsetString
        case .iso: return Self.isoString
        }
    }

    /// Human-readable form; same as `encoded`.
    @inlinable
    public var description: String { encoded }

    // MARK: Convenience

    /// Returns the sentinel for a given charset, or `nil` if not applicable.
    /// Useful when deciding which marker to emit during encoding.
    @inlinable
    public static func forCharset(_ charset: String.Encoding) -> Sentinel? {
        switch charset {
        case .utf8: return .charset
        case .isoLatin1: return .iso
        default: return nil
        }
    }

    /// If `part` exactly matches an encoded sentinel, returns it; otherwise `nil`.
    /// Handy when scanning `key=value` parts during decoding.
    public static func match(encodedPart part: String, caseInsensitive: Bool = false) -> Sentinel? {
        if caseInsensitive {
            if asciiCaseInsensitiveEquals(part, charsetString) { return .charset }
            if asciiCaseInsensitiveEquals(part, isoString) { return .iso }
            return nil
        } else {
            if part == charsetString { return .charset }
            if part == isoString { return .iso }
            return nil
        }
    }

    @inline(__always)
    private static func asciiCaseInsensitiveEquals(_ a: String, _ b: String) -> Bool {
        // Fast path: length must match.
        let au = a.utf8
        let bu = b.utf8
        guard au.count == bu.count else { return false }

        var ia = au.makeIterator()
        var ib = bu.makeIterator()
        while let x = ia.next(), let y = ib.next() {
            // Fold ASCII letters to lowercase by OR-ing 0x20; other bytes unchanged.
            let fx = x | 0x20
            let fy = y | 0x20
            if fx != fy { return false }
        }
        return true
    }
}

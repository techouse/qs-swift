import Foundation

// MARK: - Supporting Types

/// Unified scalar decoder used for **both keys and values**.
///
/// - You receive the raw token (`value`) and, when known, a `charset` (either `.utf8` or `.isoLatin1`).
/// - `kind` tells you whether the token originated from a **key** or a **value** (`.key` / `.value`).
/// - Return `nil` to represent an *absent* value; this is honored (the library does **not** fall back).
/// - When both are provided, this takes **precedence** over `legacyDecoder`.
public typealias ScalarDecoder =
    @Sendable (
        _ value: String?, _ charset: String.Encoding?, _ kind: DecodeKind?
    ) -> Any?

/// Back‑compat adapter for `(value, charset) -> Any?` decoders.
///
/// Prefer `ScalarDecoder` which also receives the `DecodeKind`. If both
/// `decoder` and `legacyDecoder` are supplied in `DecodeOptions`, the
/// `decoder` wins. This alias remains only for interop with older callers
/// and other ports.
@available(*, deprecated, message: "Use ScalarDecoder; adapt as { v, c, _ in legacy(v, c) }")
public typealias LegacyDecoder = @Sendable (_ value: String?, _ charset: String.Encoding?) -> Any?

// Legacy note: some ports exposed a ValueDecoder(value, charset) shape.
// In this Swift port, use `ScalarDecoder` instead; it also provides the DecodeKind.

/// Options that configure how query strings are *decoded* into a `[String: Any]`.
///
/// This mirrors the behavior of popular `qs` libraries while fitting Swift’s type system.
///
/// ### Highlights
/// - **Depth control:** `depth` limits how many `[]` segments become nested dictionaries.
///   With `strictDepth = false` (default), extra segments collapse into a single literal
///   path (safe, non-throwing). With `strictDepth = true`, overshoot *throws*.
/// - **List behavior:** Tune list parsing with `parseLists`, `listLimit`, `allowEmptyLists`,
///   and `allowSparseLists`.
/// - **Charset:** Use `.utf8` or `.isoLatin1`. When `charsetSentinel = true`, a leading
///   `utf8=✓` or its numeric-entity variant flips the charset automatically.
/// - **Limits:** `parameterLimit` and `listLimit` guard against pathological inputs.
/// - **Duplicates:** Choose how duplicate keys merge via `duplicates`.
///
/// ### Safety & Performance Notes
/// - Keep `depth` small for untrusted input. Extremely deep chains create large nested
///   structures; on some Swift runtimes, ARC teardown of ultra-deep maps is best done on
///   the main actor (the decoder handles that internally for very deep shapes).
/// - `parameterLimit` must be positive; `depth` must be ≥ 0.
///
/// ### Examples
/// ```swift
/// // Basic:
/// let m = try Qs.decode("a[b]=c")
/// // ["a": ["b": "c"]]
///
/// // Dot notation:
/// let m2 = try Qs.decode("a.b=c", options: .init(allowDots: true))
/// // ["a": ["b": "c"]]
/// ```
public struct DecodeOptions: @unchecked Sendable {
    // MARK: Feature toggles (private booleans with computed accessors)

    /// Set to `true` to decode dot notation in keys (e.g. `a.b=c` ⇒ `["a": ["b": "c"]]`).
    ///
    /// Prefer accessing `getAllowDots` which also considers `decodeDotInKeys`.
    private let allowDots: Bool?

    @usableFromInline internal let decoder: ScalarDecoder?
    @available(
        *, deprecated,
        message: "Use `decoder` (ScalarDecoder); this will be removed in a future major release."
    )
    @usableFromInline internal let legacyDecoder: LegacyDecoder?

    /// When `true`, encoded dot sequences (`%2E`/`%2e`) **inside key segments** are treated as
    /// literal dots for the purposes of naming (after splitting). This option **implies**
    /// dot notation (`allowDots`).
    ///
    /// Notes:
    /// - Top‑level splitting is controlled by `allowDots`. Since percent‑decoding occurs before
    ///   splitting, a top‑level `%2E` becomes a literal `.` and will split when `allowDots == true`.
    /// - Percent‑decoding in bracket segments (e.g. `a[%2E]`) happens during key decoding; the
    ///   resulting `.` participates like any other literal dot.
    private let decodeDotInKeys: Bool?

    // MARK: Public toggles

    /// Allow empty lists in the input to become `[]` in the result (instead of omitting the key).
    public let allowEmptyLists: Bool

    /// Allow sparse lists (holes); missing indices are represented as `nil`.
    /// When compacted, holes may be removed unless `allowSparseLists` is true.
    public let allowSparseLists: Bool

    /// Maximum *index* that will be materialized as a list element before falling back
    /// to a dictionary. For example, with the default `20`, `a[21]=x` decodes as
    /// `["a": ["21": "x"]]` instead of allocating a 22-element list.
    public let listLimit: Int

    /// Character encoding to use (`.utf8` or `.isoLatin1`). May be overridden by the charset sentinel.
    public let charset: String.Encoding

    /// Enable detection of `utf8=✓` (or its numeric-entity form) to override `charset`.
    public let charsetSentinel: Bool

    /// Treat commas as list separators in scalar positions (e.g., `a=b,c` ⇒ `["a": ["b","c"]]`).
    public let comma: Bool

    /// Delimiter used to split top-level pairs (default `&`). Can be `StringDelimiter` or `RegexDelimiter`.
    public let delimiter: Delimiter

    /// Maximum nesting depth for bracketed keys (e.g. `"a[b][c]"`).
    ///
    /// - Default: `5`.
    /// - When `strictDepth == false` (default): extra segments are collapsed into one literal key,
    ///   so parsing doesn’t produce unbounded depth.
    /// - When `strictDepth == true`: decoding *throws* if the limit is exceeded.
    ///
    /// WARNING: If you *must* raise this into the thousands, be aware of memory/teardown costs.
    public let depth: Int

    /// Maximum number of top-level parameters to parse. Must be positive.
    public let parameterLimit: Int

    /// How to merge duplicate keys at the same level (`.combine`, `.first`, `.last`).
    public let duplicates: Duplicates

    /// Ignore a leading `?` (common when passing `URL.query` directly).
    public let ignoreQueryPrefix: Bool

    /// Interpret HTML numeric entities (`&#...;`) when `charset == .isoLatin1`.
    public let interpretNumericEntities: Bool

    /// Disable list parsing entirely. Useful for strict “map only” modes.
    public let parseLists: Bool

    /// If `true`, exceeding `depth` throws instead of collapsing the remainder.
    public let strictDepth: Bool

    /// If `true`, values without `=` decode to `nil` (vs `""` by default).
    public let strictNullHandling: Bool

    /// If `true`, exceeding `parameterLimit` throws; otherwise parsing truncates silently.
    public let throwOnLimitExceeded: Bool

    // MARK: - Computed Properties

    /// Effective dot‑notation flag: `true` when `allowDots == true` **or** when `decodeDotInKeys == true`.
    /// This matches other ports where requesting encoded‑dot handling implicitly enables dot paths.
    public var getAllowDots: Bool {
        allowDots ?? (decodeDotInKeys == true)
    }

    /// Effective `decodeDotInKeys` value (defaults to `false`). See the property docs for behavior details.
    public var getDecodeDotInKeys: Bool {
        decodeDotInKeys ?? false
    }

    // MARK: - Initializer

    /// Create a `DecodeOptions` value.
    ///
    /// - Precondition:
    ///   - `charset` must be `.utf8` or `.isoLatin1`.
    ///   - `parameterLimit` must be > 0.
    ///   - `depth` must be ≥ 0.
    ///   - If `decodeDotInKeys == true`, then `allowDots` must be `true` (or omitted so it
    ///     defaults to `true` via `getAllowDots`). Violations trigger a precondition failure.
    ///   - If both `decoder` and `legacyDecoder` are supplied, `decoder` wins.
    public init(
        allowDots: Bool? = nil,
        decoder: ScalarDecoder? = nil,
        legacyDecoder: LegacyDecoder? = nil,
        decodeDotInKeys: Bool? = nil,
        allowEmptyLists: Bool = false,
        allowSparseLists: Bool = false,
        listLimit: Int = 20,
        charset: String.Encoding = .utf8,
        charsetSentinel: Bool = false,
        comma: Bool = false,
        delimiter: Delimiter = StringDelimiter("&"),
        depth: Int = 5,
        parameterLimit: Int = 1000,
        duplicates: Duplicates = .combine,
        ignoreQueryPrefix: Bool = false,
        interpretNumericEntities: Bool = false,
        parseLists: Bool = true,
        strictDepth: Bool = false,
        strictNullHandling: Bool = false,
        throwOnLimitExceeded: Bool = false
    ) {
        // Validate inputs
        precondition(charset == .utf8 || charset == .isoLatin1, "Invalid charset")
        precondition(parameterLimit > 0, "Parameter limit must be positive")
        precondition(depth >= 0, "depth must be >= 0")

        self.allowDots = allowDots
        self.decoder = decoder
        self.legacyDecoder = legacyDecoder
        self.decodeDotInKeys = decodeDotInKeys
        self.allowEmptyLists = allowEmptyLists
        self.allowSparseLists = allowSparseLists
        self.listLimit = listLimit
        self.charset = charset
        self.charsetSentinel = charsetSentinel
        self.comma = comma
        self.delimiter = delimiter
        self.depth = depth
        self.parameterLimit = parameterLimit
        self.duplicates = duplicates
        self.ignoreQueryPrefix = ignoreQueryPrefix
        self.interpretNumericEntities = interpretNumericEntities
        self.parseLists = parseLists
        self.strictDepth = strictDepth
        self.strictNullHandling = strictNullHandling
        self.throwOnLimitExceeded = throwOnLimitExceeded

        // Validate the relationship between decodeDotInKeys and allowDots
        let finalDecodeDotInKeys = decodeDotInKeys ?? false
        let finalAllowDots = allowDots ?? finalDecodeDotInKeys
        precondition(
            !finalDecodeDotInKeys || finalAllowDots,
            "decodeDotInKeys requires allowDots to be true"
        )
    }

    // MARK: - Methods

    /// Convenience back‑compat entry point (treat as VALUE decoding).
    /// Prefer `decodeValue(_:charset:)` in new code. Custom decoders still receive `kind = .value`.
    @available(
        *, deprecated, message: "Use decodeValue(_:charset:) or decodeKey(_:charset:) instead"
    )
    public func getDecoder(_ value: String?, charset: String.Encoding? = nil) -> Any? {
        // Back‑compat: treat this as a VALUE decode.
        return decode(value, charset ?? self.charset, .value)
    }

    /// Unified scalar decode with key/value context.
    ///
    /// Dispatch rules:
    /// 1) If `decoder` is set, it is called first and its return (including `nil`) is honored.
    /// 2) Else if `legacyDecoder` is set, it is used.
    /// 3) Else the library default `defaultDecode` runs (keys and values decode identically).
    @inlinable
    internal func decode(
        _ value: String?, _ charset: String.Encoding? = nil, _ kind: DecodeKind = .value
    ) -> Any? {
        if let dec = decoder {
            return dec(value, charset ?? self.charset, kind)
        }
        if let legacy = legacyDecoder {
            return legacy(value, charset ?? self.charset)
        }
        return defaultDecode(value, charset ?? self.charset)
    }

    /// Default library decode (keys and values are percent‑decoded the same way).
    /// Whether a `.` participates in key splitting is decided later by the parser/splitter.
    @usableFromInline
    internal func defaultDecode(_ value: String?, _ charset: String.Encoding) -> Any? {
        guard value != nil else { return nil }
        return Utils.decode(value, charset: charset)
    }

    /// Decode a key (or key segment). Always coerces the result to `String?` (mirrors Kotlin’s `toString()`).
    /// Custom decoders receive `kind = .key`.
    @inlinable
    public func decodeKey(_ value: String?, charset: String.Encoding? = nil) -> String? {
        let out = decode(value, charset ?? self.charset, .key)
        return out.map { String(describing: $0) }
    }

    /// Decode a value token (scalar). Custom decoders receive `kind = .value`.
    @inlinable
    public func decodeValue(_ value: String?, charset: String.Encoding? = nil) -> Any? {
        return decode(value, charset ?? self.charset, .value)
    }

    @inline(__always) internal var _decoder: ScalarDecoder? { decoder }

    /// Returns a copy of these options with any provided overrides.
    ///
    /// Only the parameters you pass are changed; everything else is carried over.
    /// This re-runs the same input validations as the initializer.
    ///
    /// Decoder precedence is preserved: if you don’t override them, an existing
    /// `decoder` continues to win over `legacyDecoder` in the copy.
    ///
    /// - Note:
    ///   If you set `decodeDotInKeys == true` but don’t pass `allowDots`,
    ///   this will automatically force `allowDots = true` to satisfy the precondition.
    public func copy(
        allowDots: Bool? = nil,
        decoder: ScalarDecoder? = nil,
        legacyDecoder: LegacyDecoder? = nil,
        decodeDotInKeys: Bool? = nil,
        allowEmptyLists: Bool? = nil,
        allowSparseLists: Bool? = nil,
        listLimit: Int? = nil,
        charset: String.Encoding? = nil,
        charsetSentinel: Bool? = nil,
        comma: Bool? = nil,
        delimiter: Delimiter? = nil,
        depth: Int? = nil,
        parameterLimit: Int? = nil,
        duplicates: Duplicates? = nil,
        ignoreQueryPrefix: Bool? = nil,
        interpretNumericEntities: Bool? = nil,
        parseLists: Bool? = nil,
        strictDepth: Bool? = nil,
        strictNullHandling: Bool? = nil,
        throwOnLimitExceeded: Bool? = nil
    ) -> DecodeOptions {
        // Resolve the dots flags while maintaining the invariant:
        // decodeDotInKeys => allowDots
        let newDecodeDot = decodeDotInKeys ?? self.getDecodeDotInKeys
        let newAllowDots = allowDots ?? (self.getAllowDots || newDecodeDot)

        return DecodeOptions(
            allowDots: newAllowDots,
            decoder: decoder ?? self._decoder,
            legacyDecoder: legacyDecoder ?? self.legacyDecoder,
            decodeDotInKeys: newDecodeDot,
            allowEmptyLists: allowEmptyLists ?? self.allowEmptyLists,
            allowSparseLists: allowSparseLists ?? self.allowSparseLists,
            listLimit: listLimit ?? self.listLimit,
            charset: charset ?? self.charset,
            charsetSentinel: charsetSentinel ?? self.charsetSentinel,
            comma: comma ?? self.comma,
            delimiter: delimiter ?? self.delimiter,
            depth: depth ?? self.depth,
            parameterLimit: parameterLimit ?? self.parameterLimit,
            duplicates: duplicates ?? self.duplicates,
            ignoreQueryPrefix: ignoreQueryPrefix ?? self.ignoreQueryPrefix,
            interpretNumericEntities: interpretNumericEntities ?? self.interpretNumericEntities,
            parseLists: parseLists ?? self.parseLists,
            strictDepth: strictDepth ?? self.strictDepth,
            strictNullHandling: strictNullHandling ?? self.strictNullHandling,
            throwOnLimitExceeded: throwOnLimitExceeded ?? self.throwOnLimitExceeded
        )
    }
}

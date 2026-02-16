import Foundation

// MARK: - Supporting typealiases

/// A closure that turns an arbitrary value into a percent-encoded string for
/// inclusion in a query string. If `nil`, the library falls back to
/// `Utils.encode(_:charset:format:)`.
///
/// - Parameters:
///   - value: The value to encode (may be `nil` when `strictNullHandling` is used).
///   - charset: The charset to use for percent-encoding (`.utf8` or `.isoLatin1`).
///   - format: The space-encoding strategy (RFC3986 = `%20`, RFC1738 = `+`).
/// - Returns: The encoded string (do **not** include the key or `=` here).
public typealias ValueEncoder =
    @Sendable (
        _ value: Any?, _ charset: String.Encoding?, _ format: Format?
    ) ->
    String

/// A closure that turns a `Date` into a string. If `nil`, the library uses an
/// ISO-8601 formatter (with fractional seconds iff present).
public typealias DateSerializer = @Sendable (_ date: Date) -> String

/// A comparator used to sort parameter keys deterministically. Return `<0` when
/// `a` should be ordered before `b`, `0` for equal, `>0` for after. When `nil`,
/// the encoder preserves the traversal order of the input container.
public typealias Sorter = @Sendable (_ a: Any?, _ b: Any?) -> Int

// MARK: - EncodeOptions

/// Options that configure how values are encoded into a query string.
///
/// ### Ordering
/// - If `sort` is provided, it decides ordering (applied where relevant).
/// - If `sort == nil`, the encoder preserves the traversal order of the input
///   container. Use `OrderedDictionary` (or pass a sorted list of keys) when you
///   want stable insertion order.
///
/// ### Lists
/// - `listFormat` selects how arrays are rendered (`a[0]=x`, `a[]=x`, `a=x`, or `a=x,y`).
/// - `indices` is deprecated; it maps to `.indices`/`.repeatKey` when `listFormat` is `nil`.
///
/// ### Nulls
/// - By default, `nil` encodes as `a=` (empty string).
/// - With `strictNullHandling == true`, `nil` encodes as just `a` (no `=`).
///
/// ### Charset & spaces
/// - `format: .rfc3986` (default) encodes spaces as `%20`.
/// - `format: .rfc1738` encodes spaces as `+`.
public struct EncodeOptions: @unchecked Sendable {
    /// A custom encoder for values. If `nil`, `Utils.encode` is used.
    /// Note: The encoder is used only when `encode == true`.
    private let encoder: ValueEncoder?

    /// A custom serializer for `Date` values. If `nil`, an ISO-8601 formatter is used.
    private let dateSerializer: DateSerializer?

    /// The list encoding format. If `nil`, falls back to `indices` (deprecated) or `.indices`.
    private let listFormat: ListFormat?

    /// Deprecated; use `listFormat`. When present and `listFormat == nil`,
    /// `true` ⇒ `.indices`, `false` ⇒ `.repeatKey`.
    @usableFromInline
    internal let _indices: Bool?

    /// Deprecated: Use `listFormat` instead.
    @available(*, deprecated, message: "Use listFormat instead", renamed: "listFormat")
    public var indices: Bool? { _indices }

    /// Use dot notation for nested keys (e.g. `a.b=c` instead of `a[b]=c`)
    /// when `encode == false`. When `encode == true`, dot characters are percent-encoded
    /// unless `encodeDotInKeys == false`.
    private let allowDots: Bool?

    /// When `true`, prefix the output with a leading `?`.
    public let addQueryPrefix: Bool

    /// When `true`, render empty arrays as `foo[]` (instead of omitting them).
    public let allowEmptyLists: Bool

    /// Charset to use for percent-encoding (`.utf8` or `.isoLatin1`).
    public let charset: String.Encoding

    /// When `true`, prepend a Rails-style sentinel (`utf8=✓` or numeric entity) to advertise charset.
    public let charsetSentinel: Bool

    /// Delimiter between `key=value` pairs (e.g. `"&"` or `";"`).
    public let delimiter: String

    /// When `false`, do not percent-encode keys/values (useful for already-encoded data).
    public let encode: Bool

    /// When `true`, encode `.` in keys as `%2E`. (Values are unaffected unless you encode them yourself.)
    ///
    /// - Note: If you also set `encodeValuesOnly == true`, only **keys** are encoded by the library.
    public let encodeDotInKeys: Bool

    /// When `true`, encode only **values** and not keys.
    /// Combine with `encodeDotInKeys` if you need `.` in keys to be encoded too.
    public let encodeValuesOnly: Bool

    /// Space-encoding strategy: RFC3986 (`%20`, default) or RFC1738 (`+`).
    public let format: Format

    /// Filter which keys are included / how values are transformed (see `Filter`).
    public let filter: Filter?

    /// When `true`, omit keys whose value is `nil`.
    public let skipNulls: Bool

    /// When `true`, distinguish `nil` and `""` (`a` vs `a=`).
    public let strictNullHandling: Bool

    /// If `.comma` list format is used, setting this to `true` appends `[]` for single-element lists,
    /// so they round-trip back to a list on decode (e.g. `a[]=x` instead of `a=x`).
    public let commaRoundTrip: Bool?

    /// If `.comma` list format is used, drop `nil`/`NSNull` items before joining to produce a compact payload.
    public let commaCompactNulls: Bool

    /// Sort function for keys when you want deterministic output independent of input order.
    ///
    /// If `nil`, the encoder preserves the input traversal order (see note above).
    public let sort: Sorter?

    // MARK: - Computed convenience

    /// Whether dot-notation is allowed. If unspecified, it mirrors `encodeDotInKeys`.
    public var getAllowDots: Bool { allowDots ?? encodeDotInKeys }

    /// The effective list format. Honors `listFormat` first; otherwise maps `indices` to
    /// `.indices`/`.repeatKey`; finally defaults to `.indices`.
    public var getListFormat: ListFormat {
        if let listFormat { return listFormat }
        if let indicesValue = _indices { return indicesValue ? .indices : .repeatKey }
        return .indices
    }

    /// Formatter used for percent-encoding according to `format`.
    public var formatter: Formatter { format.formatter }

    // MARK: - Init

    /// Creates a new set of encoding options.
    ///
    /// - Parameters:
    ///   - encoder: Custom value encoder. If `nil`, the library’s encoder is used.
    ///   - dateSerializer: Custom `Date` serializer. If `nil`, ISO-8601 is used.
    ///   - listFormat: Array rendering style (`.indices`, `.brackets`, `.repeatKey`, `.comma`).
    ///   - indices: **Deprecated**. Only used when `listFormat == nil`.
    ///   - allowDots: Enable dot notation in *unencoded* output (when `encode == false`).
    ///   - addQueryPrefix: Prepend `?` to the result.
    ///   - allowEmptyLists: Render empty arrays as `foo[]` instead of omitting.
    ///   - charset: `.utf8` (default) or `.isoLatin1`.
    ///   - charsetSentinel: Prepend a Rails-style `utf8=...` sentinel parameter.
    ///   - delimiter: Pair delimiter (default `"&"`).
    ///   - encode: When `false`, do not percent-encode keys/values.
    ///   - encodeDotInKeys: Percent-encode `.` in keys (`.` → `%2E`) when `encode == true`.
    ///   - encodeValuesOnly: Encode only values, not keys.
    ///   - format: RFC3986 (space as `%20`) or RFC1738 (space as `+`).
    ///   - filter: Include/transform keys via `Filter`.
    ///   - skipNulls: Omit keys with `nil` values.
    ///   - strictNullHandling: Distinguish `nil` (`a`) from empty `""` (`a=`).
    ///   - commaRoundTrip: With `.comma`, ensure single-element lists keep `[]` for round-trip.
    ///   - commaCompactNulls: With `.comma`, drop `nil` entries before joining to avoid empty slots.
    ///   - sort: Optional comparator for deterministic key ordering.
    public init(
        encoder: ValueEncoder? = nil,
        dateSerializer: DateSerializer? = nil,
        listFormat: ListFormat? = nil,
        indices: Bool? = nil,
        allowDots: Bool? = nil,
        addQueryPrefix: Bool = false,
        allowEmptyLists: Bool = false,
        charset: String.Encoding = .utf8,
        charsetSentinel: Bool = false,
        delimiter: String = "&",
        encode: Bool = true,
        encodeDotInKeys: Bool = false,
        encodeValuesOnly: Bool = false,
        format: Format = .rfc3986,
        filter: Filter? = nil,
        skipNulls: Bool = false,
        strictNullHandling: Bool = false,
        commaRoundTrip: Bool? = nil,
        commaCompactNulls: Bool = false,
        sort: Sorter? = nil
    ) {
        // Validate charset (.utf8 or .isoLatin1)
        precondition(charset == .utf8 || charset == .isoLatin1, "Invalid charset")

        self.encoder = encoder
        self.dateSerializer = dateSerializer
        self.listFormat = listFormat
        self._indices = indices
        self.allowDots = allowDots
        self.addQueryPrefix = addQueryPrefix
        self.allowEmptyLists = allowEmptyLists
        self.charset = charset
        self.charsetSentinel = charsetSentinel
        self.delimiter = delimiter
        self.encode = encode
        self.encodeDotInKeys = encodeDotInKeys
        self.encodeValuesOnly = encodeValuesOnly
        self.format = format
        self.filter = filter
        self.skipNulls = skipNulls
        self.strictNullHandling = strictNullHandling
        self.commaRoundTrip = commaRoundTrip
        self.commaCompactNulls = commaCompactNulls
        self.sort = sort
    }

    // MARK: - Helpers

    /// Encodes a value to a `String`.
    ///
    /// If a custom `encoder` is provided, it is used; otherwise this calls
    /// `Utils.encode(_:charset:format:)`.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - charset: Optional override; defaults to `self.charset`.
    ///   - format: Optional override; defaults to `self.format`.
    /// - Returns: The encoded string.
    public func getEncoder(
        _ value: Any?,
        charset: String.Encoding? = nil,
        format: Format? = nil
    ) -> String {
        let charsetToUse = charset ?? self.charset
        let formatToUse = format ?? self.format
        if let encoder {
            return encoder(value, charsetToUse, formatToUse)
        }
        return Utils.encode(value, charset: charsetToUse, format: formatToUse)
    }

    /// Serializes a `Date` to a `String`.
    ///
    /// If `dateSerializer` is provided, it is used; otherwise an `ISO8601DateFormatter`
    /// is created per call and configured to include fractional seconds iff the date has them.
    ///
    /// - Parameter date: The date to serialize.
    /// - Returns: A string (e.g. `1970-01-01T00:00:00Z` or with `.sss` if needed).
    public func getDateSerializer(_ date: Date) -> String {
        if let dateSerializer { return dateSerializer(date) }

        // Avoid shared static formatters (non-Sendable) to satisfy concurrency checks.
        let hasFractionalMillis =
            date.timeIntervalSince1970
            .truncatingRemainder(dividingBy: 1) != 0
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions =
            hasFractionalMillis
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return fmt.string(from: date)
    }

    /// Returns a new `EncodeOptions`, overriding only the fields you supply.
    ///
    /// For optional fields, parameters are **double optional**:
    /// - Pass `nil` (default) to keep the current value.
    /// - Pass `.some(nil)` to explicitly set the field to `nil`.
    ///
    /// Example:
    /// ```swift
    /// let a = EncodeOptions()
    /// let b = a.copy(listFormat: .some(.brackets), sort: .some(nil)) // set listFormat, clear sort
    /// ```
    public func copy(
        encoder: ValueEncoder?? = nil,
        dateSerializer: DateSerializer?? = nil,
        listFormat: ListFormat?? = nil,
        indices: Bool?? = nil,  // deprecated; honored if listFormat == nil
        allowDots: Bool?? = nil,

        addQueryPrefix: Bool? = nil,
        allowEmptyLists: Bool? = nil,
        charset: String.Encoding? = nil,
        charsetSentinel: Bool? = nil,
        delimiter: String? = nil,
        encode: Bool? = nil,
        encodeDotInKeys: Bool? = nil,
        encodeValuesOnly: Bool? = nil,
        format: Format? = nil,
        filter: Filter?? = nil,
        skipNulls: Bool? = nil,
        strictNullHandling: Bool? = nil,
        commaRoundTrip: Bool?? = nil,
        commaCompactNulls: Bool? = nil,
        sort: Sorter?? = nil
    ) -> EncodeOptions {
        @inline(__always)
        func pick<T>(_ new: T??, _ cur: T?) -> T? {
            // If caller passed a value (even if it's `.some(nil)`), use it; otherwise keep current.
            if let new { return new } else { return cur }
        }

        return EncodeOptions(
            encoder: pick(encoder, self.encoder),
            dateSerializer: pick(dateSerializer, self.dateSerializer),
            listFormat: pick(listFormat, self.listFormat),
            indices: pick(indices, self._indices),
            allowDots: pick(allowDots, self.allowDots),

            addQueryPrefix: addQueryPrefix ?? self.addQueryPrefix,
            allowEmptyLists: allowEmptyLists ?? self.allowEmptyLists,
            charset: charset ?? self.charset,
            charsetSentinel: charsetSentinel ?? self.charsetSentinel,
            delimiter: delimiter ?? self.delimiter,
            encode: encode ?? self.encode,
            encodeDotInKeys: encodeDotInKeys ?? self.encodeDotInKeys,
            encodeValuesOnly: encodeValuesOnly ?? self.encodeValuesOnly,
            format: format ?? self.format,
            filter: pick(filter, self.filter),
            skipNulls: skipNulls ?? self.skipNulls,
            strictNullHandling: strictNullHandling ?? self.strictNullHandling,
            commaRoundTrip: pick(commaRoundTrip, self.commaRoundTrip),
            commaCompactNulls: commaCompactNulls ?? self.commaCompactNulls,
            sort: pick(sort, self.sort)
        )
    }
}

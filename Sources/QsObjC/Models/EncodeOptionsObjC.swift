#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Objective-C wrapper for `QsSwift.EncodeOptions`.
    ///
    /// Configure this mutable object from Obj-C or Swift and pass it into the bridge.
    /// The `swift` computed property builds an immutable `QsSwift.EncodeOptions`
    /// consumed by the core encoder.
    ///
    /// Thread-safety: not thread-safe. Configure on one thread, then use.
    @objc(QsEncodeOptions)
    @objcMembers
    public final class EncodeOptionsObjC: NSObject {

        // MARK: - Custom encoders / sorters

        /// Called to encode values (and—when `encodeValuesOnly == false`—keys) into **percent-encoded tokens**.
        /// Return just the token (no `&`, `=` or joining).
        ///
        /// - Parameters:
        ///   - value:   The value to encode. May be `nil` under strict-null handling.
        ///   - charset: `NSNumber` wrapping `String.Encoding.rawValue`, or `nil` if unspecified.
        ///   - format:  `NSNumber(0 = RFC 3986, 1 = RFC 1738)`, or `nil` if unspecified.
        ///
        /// Note: You do not need to normalize spaces here; the core applies the final
        /// space style (`%20` vs `+`) after your block runs.
        public typealias ValueEncoderBlock = (Any?, NSNumber?, NSNumber?) -> NSString
        public var valueEncoderBlock: ValueEncoderBlock? {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// If set, converts `NSDate` to an **unencoded** string before the core percent-encodes it.
        public typealias DateSerializerBlock = (NSDate) -> NSString
        public var dateSerializerBlock: DateSerializerBlock? {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Deterministic key sorter. Must return **-1**, **0**, or **+1** (like `strcmp` or `NSComparisonResult.rawValue`).
        /// If provided, this takes precedence over `sortKeysCaseInsensitively`.
        public typealias SortComparatorBlock = (Any?, Any?) -> Int
        public var sortComparatorBlock: SortComparatorBlock? {
            didSet { invalidateSwiftOptionsCache() }
        }

        // MARK: - Output formatting / behavior

        /// If true, prepend `'?'` to the encoded string (useful for building URLs).
        public var addQueryPrefix: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Accept dotted key paths (`a.b.c`) as if they were bracket paths (`a[b][c]`).
        /// For compatibility with other ports, this is OR’ed with `encodeDotInKeys` (either flag enables dots).
        public var allowDots: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// When true, include empty lists as `a[]` instead of omitting the key.
        public var allowEmptyLists: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Output character set for percent-encoding. Defaults to UTF-8.
        public var charset: UInt = String.Encoding.utf8.rawValue {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Include the `utf8=✓` sentinel (qs convention) when appropriate.
        public var charsetSentinel: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Pair delimiter between `key=value` tokens (e.g. `&` or `;`).
        public var delimiter: String = "&" {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Master switch: when false, the encoder **does not percent-encode**—useful for tests
        /// that assert exact literal output.
        public var encode: Bool = true {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Deprecated spelling kept for parity with Swift/other ports.
        /// When true, dots in **keys** are parsed/treated as path separators.
        /// `allowDots || encodeDotInKeys` is passed to Swift as `allowDots`.
        public var encodeDotInKeys: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// If true, `valueEncoderBlock` is **not** used for keys—only for values.
        public var encodeValuesOnly: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// RFC formatting (3986 vs 1738).
        public var format: FormatObjC = .rfc3986 {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Deprecated (mirrors Swift). Used only when `listFormat == nil`.
        /// `NSNumber(bool)`: `nil` = “unspecified”, `0` = false, `1` = true.
        public var indices: NSNumber? {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// List/array style (e.g. `.brackets`, `.indices`, `.comma`). If `nil`, the legacy
        /// `indices` setting above is consulted.
        ///
        /// Swift-facing storage (optional enum). Not visible to Obj-C.
        @nonobjc public var listFormat: ListFormatObjC? {
            didSet { invalidateSwiftOptionsCache() }
        }

        // Obj-C-facing boxed accessor under the same Obj-C name.
        // Obj-C will see: @property (nullable, nonatomic, strong) NSNumber *listFormat;
        @objc(listFormat)
        public var listFormatBoxed: NSNumber? {
            get { listFormat.map { NSNumber(value: $0.rawValue) } }
            set { listFormat = newValue.flatMap { ListFormatObjC(rawValue: $0.intValue) } }
        }

        /// Drop `null` values instead of serializing them.
        public var skipNulls: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// If true, a key without value encodes as `key` (and decodes as `NSNull`) rather than `key=`.
        public var strictNullHandling: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Only meaningful with `.comma` list format: when a list has a single item, append `[]`
        /// to allow it to round-trip back to an array on decode.
        public var commaRoundTrip: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Only meaningful with `.comma` list format: when true, drop `null` entries before joining.
        public var commaCompactNulls: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Convenience: provide a predictable case-insensitive A→Z sort (ties broken case-sensitively
        /// so `"A"` sorts before `"a"`). Ignored if `sortComparatorBlock` is set.
        public var sortKeysCaseInsensitively: Bool = false {
            didSet { invalidateSwiftOptionsCache() }
        }

        /// Bridges Swift’s filter options. To omit keys from Obj-C, return `UndefinedObjC`.
        public var filter: FilterObjC? {
            didSet { invalidateSwiftOptionsCache() }
        }

        private var cachedSwiftOptions: QsSwift.EncodeOptions?
        private var isSwiftOptionsCacheDirty = true

        @inline(__always)
        private func invalidateSwiftOptionsCache() {
            isSwiftOptionsCacheDirty = true
            cachedSwiftOptions = nil
        }

        // MARK: - Bridge to Swift core

        /// Internal bridge that constructs the Swift `EncodeOptions` used by the core.
        /// We also normalize dot handling so **either** Obj-C flag enables dots.
        var swift: QsSwift.EncodeOptions {
            if !isSwiftOptionsCacheDirty, let cachedSwiftOptions {
                return cachedSwiftOptions
            }

            let normalizedCharset: String.Encoding = {
                let candidate = String.Encoding(rawValue: charset)
                return (candidate == .utf8 || candidate == .isoLatin1) ? candidate : .utf8
            }()

            // Value encoder → Swift
            let swiftEncoder: QsSwift.ValueEncoder? = {
                guard let blk = valueEncoderBlock else { return nil }
                let box = _BlockBox(blk)
                return { value, charset, format in
                    let csNum = charset.map { NSNumber(value: $0.rawValue) }
                    let fmtNum = format.map { NSNumber(value: ($0 == .rfc3986 ? 0 : 1)) }
                    return box.block(value, csNum, fmtNum) as String
                }
            }()

            // Date serializer → Swift
            let swiftDateSerializer: QsSwift.DateSerializer? = {
                guard let blk = dateSerializerBlock else { return nil }
                let box = _BlockBox(blk)
                return { date in box.block(date as NSDate) as String }
            }()

            // Sorter: custom block > case-insensitive helper > nil
            let swiftSorter: QsSwift.Sorter? = {
                if let blk = sortComparatorBlock {
                    let box = _BlockBox(blk)
                    return { firstValue, secondValue in box.block(firstValue, secondValue) }  // expects -1/0/+1
                }
                if sortKeysCaseInsensitively {
                    return { firstValue, secondValue in
                        let sa = firstValue.map { String(describing: $0) } ?? ""
                        let sb = secondValue.map { String(describing: $0) } ?? ""
                        let primary = sa.caseInsensitiveCompare(sb)
                        if primary != .orderedSame { return primary.rawValue }
                        // Tie-breaker to make ordering deterministic: binary, case-sensitive
                        if sa == sb { return 0 }
                        return sa < sb ? -1 : 1
                    }
                }
                return nil
            }()

            let built = QsSwift.EncodeOptions(
                encoder: swiftEncoder,
                dateSerializer: swiftDateSerializer,

                // List format & legacy indices
                listFormat: listFormat?.swift,
                indices: indices?.boolValue,

                // Dot handling: either flag enables it (compat with other ports).
                allowDots: allowDots || encodeDotInKeys,

                // General formatting/behavior
                addQueryPrefix: addQueryPrefix,
                allowEmptyLists: allowEmptyLists,
                charset: normalizedCharset,
                charsetSentinel: charsetSentinel,
                delimiter: delimiter,
                encode: encode,
                encodeDotInKeys: encodeDotInKeys,
                encodeValuesOnly: encodeValuesOnly,
                format: format.swift,
                filter: filter?.swift,
                skipNulls: skipNulls,
                strictNullHandling: strictNullHandling,
                commaRoundTrip: commaRoundTrip,
                commaCompactNulls: commaCompactNulls,

                // Sorting
                sort: swiftSorter
            )

            cachedSwiftOptions = built
            isSwiftOptionsCacheDirty = false
            return built
        }

        // MARK: - Swift convenience

        /// Swift-only helper for fluent configuration:
        ///
        /// ```swift
        /// let opts = EncodeOptionsObjC().with {
        ///   $0.encode = false
        ///   $0.allowDots = true
        /// }
        /// ```
        @discardableResult
        func with(_ configure: (EncodeOptionsObjC) -> Void) -> Self {
            configure(self)
            return self
        }
    }
#endif

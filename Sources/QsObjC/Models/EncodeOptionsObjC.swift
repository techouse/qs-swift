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
public final class EncodeOptionsObjC: NSObject, @unchecked Sendable {

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
    public var valueEncoderBlock: ValueEncoderBlock?

    /// If set, converts `NSDate` to an **unencoded** string before the core percent-encodes it.
    public typealias DateSerializerBlock = (NSDate) -> NSString
    public var dateSerializerBlock: DateSerializerBlock?

    /// Deterministic key sorter. Must return **-1**, **0**, or **+1** (like `strcmp` or `NSComparisonResult.rawValue`).
    /// If provided, this takes precedence over `sortKeysCaseInsensitively`.
    public typealias SortComparatorBlock = (Any?, Any?) -> Int
    public var sortComparatorBlock: SortComparatorBlock?

    // MARK: - Output formatting / behavior

    /// If true, prepend `'?'` to the encoded string (useful for building URLs).
    public var addQueryPrefix: Bool = false

    /// Accept dotted key paths (`a.b.c`) as if they were bracket paths (`a[b][c]`).
    /// For compatibility with other ports, this is OR’ed with `encodeDotInKeys` (either flag enables dots).
    public var allowDots: Bool = false

    /// When true, include empty lists as `a[]` instead of omitting the key.
    public var allowEmptyLists: Bool = false

    /// Output character set for percent-encoding. Defaults to UTF-8.
    public var charset: UInt = String.Encoding.utf8.rawValue

    /// Include the `utf8=✓` sentinel (qs convention) when appropriate.
    public var charsetSentinel: Bool = false

    /// Pair delimiter between `key=value` tokens (e.g. `&` or `;`).
    public var delimiter: String = "&"

    /// Master switch: when false, the encoder **does not percent-encode**—useful for tests
    /// that assert exact literal output.
    public var encode: Bool = true

    /// Deprecated spelling kept for parity with Swift/other ports.
    /// When true, dots in **keys** are parsed/treated as path separators.
    /// `allowDots || encodeDotInKeys` is passed to Swift as `allowDots`.
    public var encodeDotInKeys: Bool = false

    /// If true, `valueEncoderBlock` is **not** used for keys—only for values.
    public var encodeValuesOnly: Bool = false

    /// RFC formatting (3986 vs 1738).
    public var format: FormatObjC = .rfc3986

    /// Deprecated (mirrors Swift). Used only when `listFormat == nil`.
    /// `NSNumber(bool)`: `nil` = “unspecified”, `0` = false, `1` = true.
    public var indices: NSNumber? = nil

    /// List/array style (e.g. `.brackets`, `.indices`, `.comma`). If `nil`, the legacy
    /// `indices` setting above is consulted.
    public var listFormat: ListFormatObjC? = nil

    /// Drop `null` values instead of serializing them.
    public var skipNulls: Bool = false

    /// If true, a key without value encodes as `key` (and decodes as `NSNull`) rather than `key=`.
    public var strictNullHandling: Bool = false

    /// Only meaningful with `.comma` list format: when a list has a single item, append `[]`
    /// to allow it to round-trip back to an array on decode.
    public var commaRoundTrip: Bool = false

    /// Convenience: provide a predictable case-insensitive A→Z sort (ties broken case-sensitively
    /// so `"A"` sorts before `"a"`). Ignored if `sortComparatorBlock` is set.
    public var sortKeysCaseInsensitively: Bool = false

    /// Bridges Swift’s filter options. To omit keys from Obj-C, return `UndefinedObjC`.
    public var filter: FilterObjC? = nil

    // MARK: - Bridge to Swift core

    /// Internal bridge that constructs the Swift `EncodeOptions` used by the core.
    /// We also normalize dot handling so **either** Obj-C flag enables dots.
    var swift: QsSwift.EncodeOptions {
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
                return { a, b in box.block(a, b) }  // expects -1/0/+1
            }
            if sortKeysCaseInsensitively {
                return { a, b in
                    let sa = a.map { String(describing: $0) } ?? ""
                    let sb = b.map { String(describing: $0) } ?? ""
                    let primary = sa.caseInsensitiveCompare(sb)
                    if primary != .orderedSame { return primary.rawValue }
                    // Tie-breaker to make ordering deterministic: binary, case-sensitive
                    if sa == sb { return 0 }
                    return sa < sb ? -1 : 1
                }
            }
            return nil
        }()

        return QsSwift.EncodeOptions(
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
            charset: String.Encoding(rawValue: charset),
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

            // Sorting
            sort: swiftSorter
        )
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

import Foundation
import QsSwift

@objc(QsEncodeOptions)
@objcMembers
public final class EncodeOptionsObjC: NSObject, @unchecked Sendable {
    public typealias ValueEncoderBlock = (Any?, NSNumber?, NSNumber?) -> NSString
    public typealias DateSerializerBlock = (NSDate) -> NSString
    /// Comparator returning -1, 0, +1 (like `strcmp` / `NSComparisonResult.rawValue`)
    public typealias SortComparatorBlock = (Any?, Any?) -> Int

    /// If set, used to encode values (and optionally keys if `encodeValuesOnly == false`).
    /// Params:
    ///  - value:     The value to encode (may be `nil` under strict-null handling).
    ///  - charset:   NSNumber(rawValue: String.Encoding.rawValue) or nil.
    ///  - format:    NSNumber(0 = RFC 3986, 1 = RFC 1738) or nil.
    /// Return: The encoded token (without joining or adding delimiters).
    ///
    /// Note: The block should return a *percent-encoded* token for the chosen charset.
    /// The core still applies the final "space style" (RFC3986 `%20` vs RFC1738 `+`)
    /// via its formatter, so you generally do not need to handle space normalization
    /// here. See tests for examples mapping raw scalars to `%xx` sequences.
    public var valueEncoderBlock: ValueEncoderBlock?

    /// If set, used to serialize `Date` values to strings before encoding.
    /// Return an unencoded string (the encoder will percent-encode it if needed).
    public var dateSerializerBlock: DateSerializerBlock?

    /// If set, used to deterministically order keys. Must return -1, 0, or +1.
    /// Takes precedence over `sortKeysCaseInsensitively`. Return values outside
    /// {-1,0,1} will be signum-clamped.
    public var sortComparatorBlock: SortComparatorBlock?

    public var addQueryPrefix: Bool = false
    public var allowDots: Bool = false
    public var allowEmptyLists: Bool = false
    public var charset: UInt = String.Encoding.utf8.rawValue
    public var charsetSentinel: Bool = false
    /// Pair delimiter between tokens (e.g. &, ;).
    public var delimiter: String = "&"
    public var encode: Bool = true
    public var encodeDotInKeys: Bool = false
    /// If true, your valueEncoderBlock is not used for keys.
    public var encodeValuesOnly: Bool = false
    public var format: FormatObjC = .rfc3986
    /// Deprecated (mirrors Swift). Only used when `listFormat == nil`.
    /// NSNumber<bool>: nil = "unspecified", 0 = false, 1 = true.
    public var indices: NSNumber? = nil
    public var listFormat: ListFormatObjC? = nil
    public var skipNulls: Bool = false
    public var strictNullHandling: Bool = false
    /// Only meaningful when `listFormat == .comma`: single-item lists append `[]`
    /// to round-trip back to arrays on decode.
    public var commaRoundTrip: Bool = false
    /// Convenience: if true, provide a case-insensitive A→Z sorter (ties broken by case-sensitive compare so "A" sorts before "a").
    public var sortKeysCaseInsensitively: Bool = false
    /// Bridges FunctionFilter / IterableFilter. Return QsUndefined in Obj-C via UndefinedObjC to omit keys.
    public var filter: FilterObjC? = nil

    var swift: QsSwift.EncodeOptions {
        // Value encoder
        let swiftEncoder: QsSwift.ValueEncoder? = {
            guard let blk = valueEncoderBlock else { return nil }
            let box = _BlockBox(blk)
            return { value, charset, format in
                let csNum = charset.map { NSNumber(value: $0.rawValue) }
                let fmtNum = format.map { NSNumber(value: ($0 == .rfc3986 ? 0 : 1)) }
                return box.block(value, csNum, fmtNum) as String
            }
        }()

        // Date serializer
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
                    // Tie-breaker to make order deterministic: binary, case-sensitive
                    if sa == sb { return 0 }
                    return sa < sb ? -1 : 1
                }
            }
            return nil
        }()

        return QsSwift.EncodeOptions(
            encoder: swiftEncoder,
            dateSerializer: swiftDateSerializer,
            listFormat: listFormat?.swift,
            indices: indices?.boolValue,
            // Mirror Swift default: if allowDots is unspecified, it behaves like encodeDotInKeys
            allowDots: allowDots || encodeDotInKeys,
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
            sort: swiftSorter
        )
    }
}

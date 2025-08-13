import Foundation
import QsSwift

@objc(QsEncodeOptions)
@objcMembers
public final class EncodeOptionsObjC: NSObject, @unchecked Sendable {
    public typealias ValueEncoderBlock = (Any?, NSNumber?, NSNumber?) -> NSString
    public typealias DateSerializerBlock = (NSDate) -> NSString

    /// If set, used to encode values (and optionally keys if `encodeValuesOnly == false`).
    /// Params:
    ///  - value:     The value to encode (may be `nil` under strict-null handling).
    ///  - charset:   NSNumber(rawValue: String.Encoding.rawValue) or nil.
    ///  - format:    NSNumber(0 = RFC 3986, 1 = RFC 1738) or nil.
    /// Return: The encoded token (without joining or adding delimiters).
    public var valueEncoderBlock: ValueEncoderBlock?

    /// If set, used to serialize `Date` values to strings before encoding.
    /// Return an unencoded string (the encoder will percent-encode it if needed).
    public var dateSerializerBlock: DateSerializerBlock?

    public var addQueryPrefix: Bool = false
    public var allowDots: Bool = false
    public var allowEmptyLists: Bool = false
    public var charset: UInt = String.Encoding.utf8.rawValue
    public var charsetSentinel: Bool = false
    public var delimiter: String = "&"
    public var encode: Bool = true
    public var encodeDotInKeys: Bool = false
    public var encodeValuesOnly: Bool = false
    public var format: FormatObjC = .rfc3986
    public var indices: NSNumber? = nil
    public var listFormat: ListFormatObjC? = nil
    public var skipNulls: Bool = false
    public var strictNullHandling: Bool = false
    public var commaRoundTrip: Bool = false
    public var sortKeysCaseInsensitively: Bool = false
    public var filter: FilterObjC? = nil

    var swift: QsSwift.EncodeOptions {
        // Bridge valueEncoderBlock → ValueEncoder?
        let swiftEncoder: QsSwift.ValueEncoder?
        if let blk = valueEncoderBlock {
            let box = _BlockBox(blk)
            swiftEncoder = { value, charset, format in
                let csNum = charset.map { NSNumber(value: $0.rawValue) }
                let fmtNum = format.map { NSNumber(value: ($0 == .rfc3986 ? 0 : 1)) }
                return box.block(value, csNum, fmtNum) as String
            }
        } else {
            swiftEncoder = nil
        }

        // Bridge dateSerializerBlock → DateSerializer?
        let swiftDateSerializer: QsSwift.DateSerializer?
        if let blk = dateSerializerBlock {
            let box = _BlockBox(blk)
            swiftDateSerializer = { date in box.block(date as NSDate) as String }
        } else {
            swiftDateSerializer = nil
        }

        // Optional sorter
        var sorter: QsSwift.Sorter? = nil
        if sortKeysCaseInsensitively {
            sorter = { @Sendable (a: Any?, b: Any?) -> Int in
                let sa = a.map { String(describing: $0) } ?? ""
                let sb = b.map { String(describing: $0) } ?? ""
                return sa.caseInsensitiveCompare(sb).rawValue
            }
        }

        return QsSwift.EncodeOptions(
            encoder: swiftEncoder,
            dateSerializer: swiftDateSerializer,
            listFormat: listFormat?.swift,
            indices: indices?.boolValue,
            // allowDots defaults to encodeDotInKeys if unset in Swift; mirror by OR-ing here
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
            sort: sorter
        )
    }
}

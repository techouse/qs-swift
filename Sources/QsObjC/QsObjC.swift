import Foundation
import Qs


// MARK: - Options (ObjC-friendly containers)

@objc(DecodeOptions)
@objcMembers
public final class DecodeOptionsObjC: NSObject {
    public var allowDots: Bool = false
    public var decodeDotInKeys: Bool = false
    public var allowEmptyLists: Bool = false
    public var allowSparseLists: Bool = false
    public var listLimit: Int = 20
    public var charset: UInt = String.Encoding.utf8.rawValue
    public var charsetSentinel: Bool = false
    public var comma: Bool = false
    public var delimiter: String = "&"
    public var depth: Int = 5
    public var parameterLimit: Int = 1000
    public var duplicates: DuplicatesObjC = .combine
    public var ignoreQueryPrefix: Bool = false
    public var interpretNumericEntities: Bool = false
    public var parseLists: Bool = true
    public var strictDepth: Bool = false
    public var strictNullHandling: Bool = false
    public var throwOnLimitExceeded: Bool = false

    var swift: DecodeOptions {
        DecodeOptions(
            allowDots: allowDots || decodeDotInKeys,
            decoder: nil,
            decodeDotInKeys: decodeDotInKeys,
            allowEmptyLists: allowEmptyLists,
            allowSparseLists: allowSparseLists,
            listLimit: listLimit,
            charset: String.Encoding(rawValue: charset),
            charsetSentinel: charsetSentinel,
            comma: comma,
            delimiter: StringDelimiter(delimiter),
            depth: depth,
            parameterLimit: parameterLimit,
            duplicates: duplicates.swift,
            ignoreQueryPrefix: ignoreQueryPrefix,
            interpretNumericEntities: interpretNumericEntities,
            parseLists: parseLists,
            strictDepth: strictDepth,
            strictNullHandling: strictNullHandling,
            throwOnLimitExceeded: throwOnLimitExceeded
        )
    }
}

@objc(EncodeOptions)
@objcMembers
public final class EncodeOptionsObjC: NSObject {
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
    /// If true, keys are sorted case-insensitively for stable output
    public var sortKeysCaseInsensitively: Bool = false

    var swift: EncodeOptions {
        var sorter: Sorter?
        if sortKeysCaseInsensitively {
            let s: Sorter = { (a: Any?, b: Any?) in
                let sa = a.map { String(describing: $0) } ?? ""
                let sb = b.map { String(describing: $0) } ?? ""
                return sa.localizedCaseInsensitiveCompare(sb).rawValue
            }
            sorter = s
        } else {
            sorter = nil
        }

        return EncodeOptions(
            encoder: nil,
            dateSerializer: nil,
            listFormat: listFormat.map { $0.swift },
            indices: indices?.boolValue,
            allowDots: allowDots,
            addQueryPrefix: addQueryPrefix,
            allowEmptyLists: allowEmptyLists,
            charset: String.Encoding(rawValue: charset),
            charsetSentinel: charsetSentinel,
            delimiter: delimiter,
            encode: encode,
            encodeDotInKeys: encodeDotInKeys,
            encodeValuesOnly: encodeValuesOnly,
            format: format.swift,
            filter: nil,
            skipNulls: skipNulls,
            strictNullHandling: strictNullHandling,
            commaRoundTrip: commaRoundTrip,
            sort: sorter
        )
    }
}

// MARK: - ObjC façade

@objcMembers
public final class QsObjC: NSObject {
    /// Decode a query string into an NSDictionary (values are bridged Foundation types).
    public static func decode(
        _ string: NSString,
        options: DecodeOptionsObjC? = nil,
        error outError: NSErrorPointer = nil
    ) -> NSDictionary? {
        do {
            let dict = try Qs.decode(string as String, options: options?.swift ?? DecodeOptions())
            return dict as NSDictionary
        } catch {
            outError?.pointee = error as NSError
            return nil
        }
    }

    /// Encode a Foundation container (NSDictionary/NSArray) into a query string.
    public static func encode(
        _ object: Any,
        options: EncodeOptionsObjC? = nil,
        error outError: NSErrorPointer = nil
    ) -> NSString? {
        do {
            let str = try Qs.encode(object, options: options?.swift ?? EncodeOptions())
            return str as NSString
        } catch {
            outError?.pointee = error as NSError
            return nil
        }
    }
}

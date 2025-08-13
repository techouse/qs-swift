import Foundation
import QsSwift

@objc(QsDecodeOptions)
@objcMembers
public final class DecodeOptionsObjC: NSObject, @unchecked Sendable {
    public typealias ValueDecoderBlock = (NSString?, NSNumber?) -> Any?

    /// If set, used to decode a single percent-encoded scalar before it’s interpreted.
    /// Params:
    ///  - string:  Raw token (may be nil).
    ///  - charset: NSNumber(rawValue: String.Encoding.rawValue) or nil.
    public var valueDecoderBlock: ValueDecoderBlock?

    public var allowDots: Bool = false
    public var decodeDotInKeys: Bool = false
    public var allowEmptyLists: Bool = false
    public var allowSparseLists: Bool = false
    public var listLimit: Int = 20
    public var charset: UInt = String.Encoding.utf8.rawValue
    public var charsetSentinel: Bool = false
    public var comma: Bool = false
    public var delimiter: DelimiterObjC = .ampersand
    public var depth: Int = 5
    public var parameterLimit: Int = 1000
    public var duplicates: DuplicatesObjC = .combine
    public var ignoreQueryPrefix: Bool = false
    public var interpretNumericEntities: Bool = false
    public var parseLists: Bool = true
    public var strictDepth: Bool = false
    public var strictNullHandling: Bool = false
    public var throwOnLimitExceeded: Bool = false

    var swift: QsSwift.DecodeOptions {
        // Bridge valueDecoderBlock → ValueDecoder?
        let swiftDecoder: QsSwift.ValueDecoder?
        if let blk = valueDecoderBlock {
            let box = _BlockBox(blk)
            swiftDecoder = { str, charset in
                let csNum = charset.map { NSNumber(value: $0.rawValue) }
                return box.block(str as NSString?, csNum)
            }
        } else {
            swiftDecoder = nil
        }

        return QsSwift.DecodeOptions(
            allowDots: allowDots || decodeDotInKeys,
            decoder: swiftDecoder,
            decodeDotInKeys: decodeDotInKeys,
            allowEmptyLists: allowEmptyLists,
            allowSparseLists: allowSparseLists,
            listLimit: listLimit,
            charset: String.Encoding(rawValue: charset),
            charsetSentinel: charsetSentinel,
            comma: comma,
            delimiter: delimiter.swift,
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

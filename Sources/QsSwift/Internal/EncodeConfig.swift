import Foundation

internal struct EncodeConfig {
    let generateArrayPrefix: ListFormatGenerator
    let listFormat: ListFormat
    let hasCustomGenerator: Bool
    let commaRoundTrip: Bool
    let commaCompactNulls: Bool
    let allowEmptyLists: Bool
    let strictNullHandling: Bool
    let skipNulls: Bool
    let encodeDotInKeys: Bool
    let encoder: ValueEncoder?
    let serializeDate: DateSerializer?
    let sort: Sorter?
    let filter: Filter?
    let allowDots: Bool
    let format: Format
    let formatter: Formatter
    let encodeValuesOnly: Bool
    let charset: String.Encoding

    var isCommaListFormat: Bool {
        listFormat == .comma
    }

    func withEncoder(_ nextEncoder: ValueEncoder?) -> EncodeConfig {
        EncodeConfig(
            generateArrayPrefix: generateArrayPrefix,
            listFormat: listFormat,
            hasCustomGenerator: hasCustomGenerator,
            commaRoundTrip: commaRoundTrip,
            commaCompactNulls: commaCompactNulls,
            allowEmptyLists: allowEmptyLists,
            strictNullHandling: strictNullHandling,
            skipNulls: skipNulls,
            encodeDotInKeys: encodeDotInKeys,
            encoder: nextEncoder,
            serializeDate: serializeDate,
            sort: sort,
            filter: filter,
            allowDots: allowDots,
            format: format,
            formatter: formatter,
            encodeValuesOnly: encodeValuesOnly,
            charset: charset
        )
    }
}

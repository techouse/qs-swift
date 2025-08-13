import QsSwift

@objc(QsListFormat)
public enum ListFormatObjC: Int {
    case brackets, indices, repeatKey, comma

    var swift: QsSwift.ListFormat {
        switch self {
        case .brackets: return .brackets
        case .indices: return .indices
        case .repeatKey: return .repeatKey
        case .comma: return .comma
        }
    }
}

import QsSwift

@objc(QsDuplicates)
public enum DuplicatesObjC: Int {
    case combine, first, last

    var swift: Duplicates {
        switch self {
        case .combine: return .combine
        case .first: return .first
        case .last: return .last
        }
    }
}

#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import QsSwift

    /// Objective-C mirror of Swift `QsSwift.ListFormat`.
    ///
    /// Controls how arrays/lists are rendered in query strings:
    /// - `brackets`   → `a[]=1&a[]=2`
    /// - `indices`    → `a[0]=1&a[1]=2`
    /// - `repeatKey`  → `a=1&a=2`
    /// - `comma`      → `a=1,2`  (see `EncodeOptionsObjC.commaRoundTrip` for single-item round-tripping)
    ///
    /// Raw values are intentionally stable for easy boxing/unboxing via `NSNumber`.
    @objc(QsListFormat)
    public enum ListFormatObjC: Int {
        case brackets
        case indices
        case repeatKey
        case comma

        /// Bridge to the Swift counterpart for internal use.
        var swift: QsSwift.ListFormat {
            switch self {
            case .brackets: return .brackets
            case .indices: return .indices
            case .repeatKey: return .repeatKey
            case .comma: return .comma
            }
        }
    }

    // Nice debug string parity when printing from Swift.
    extension ListFormatObjC: CustomStringConvertible {
        public var description: String {
            switch self {
            case .brackets: return "brackets"
            case .indices: return "indices"
            case .repeatKey: return "repeatKey"
            case .comma: return "comma"
            }
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

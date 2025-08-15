#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import QsSwift

    /// Objective-C mirror of Swift `QsSwift.Duplicates`.
    ///
    /// Controls how **duplicate keys** are handled during decoding:
    /// - `combine`: collect all values under the same key (typically into arrays),
    ///              e.g. `a=1&a=2` → `["a": ["1", "2"]]`.
    /// - `first`:   keep only the **first** occurrence of each key,
    ///              e.g. `a=1&a=2` → `["a": "1"]`.
    /// - `last`:    keep only the **last** occurrence of each key,
    ///              e.g. `a=1&a=2` → `["a": "2"]`.
    ///
    /// Raw values are stable and bridge cleanly via `NSNumber` in Obj-C.
    @objc(QsDuplicates)
    public enum DuplicatesObjC: Int {
        case combine
        case first
        case last

        /// Bridge to the Swift counterpart.
        var swift: QsSwift.Duplicates {
            switch self {
            case .combine: return .combine
            case .first: return .first
            case .last: return .last
            }
        }
    }

    // Nice string for logs / debugging parity with Swift.
    extension DuplicatesObjC: CustomStringConvertible {
        public var description: String {
            switch self {
            case .combine: return "combine"
            case .first: return "first"
            case .last: return "last"
            }
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import QsSwift

    /// Objective-C mirror of Swift ``QsSwift.DecodeKind``.
    ///
    /// Indicates the decoding context for a scalar token:
    /// - `key`:    decode a key (or key segment); implementations often *preserve*
    ///             percent-encoded dots (`%2E`/`%2e`) until after key splitting.
    /// - `value`:  decode a value normally (regular percent-decoding / charset rules).
    ///
    /// Raw values are stable and bridge cleanly via `NSNumber` in Obj-C.
    @objc(QsDecodeKind)
    public enum DecodeKindObjC: Int {
        case key
        case value

        /// Bridge to the Swift counterpart.
        public var swift: QsSwift.DecodeKind {
            switch self {
            case .key: return .key
            case .value: return .value
            }
        }

        /// Create from the Swift counterpart (round-trip convenience).
        public init(_ swift: QsSwift.DecodeKind) {
            switch swift {
            case .key: self = .key
            case .value: self = .value
            }
        }
    }

    /// Nice string for logs / debugging parity with Swift.
    extension DecodeKindObjC: CustomStringConvertible {
        public var description: String {
            switch self {
            case .key: return "key"
            case .value: return "value"
            }
        }
    }
#endif

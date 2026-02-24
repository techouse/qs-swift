import Foundation

internal enum EncodePhase {
    case start
    case iterate
    case awaitChild
}

internal enum EncodeKeyState {
    case none
    case single(Any)
    case many([Any])
}

internal enum EncodedValuesBuffer {
    case empty
    case single(Any)
    case many([Any])

    @inline(__always)
    mutating func append(_ value: Any) {
        switch self {
        case .empty:
            self = .single(value)
        case .single(let current):
            self = .many([current, value])
        case .many(var list):
            list.append(value)
            self = .many(list)
        }
    }

    @inline(__always)
    mutating func append(contentsOf values: [Any]) {
        guard !values.isEmpty else { return }

        switch self {
        case .empty:
            if values.count == 1, let first = values.first {
                self = .single(first)
            } else {
                self = .many(values)
            }
        case .single(let current):
            var list = [Any]()
            list.reserveCapacity(values.count + 1)
            list.append(current)
            list.append(contentsOf: values)
            self = .many(list)
        case .many(var list):
            list.append(contentsOf: values)
            self = .many(list)
        }
    }

    @inline(__always)
    func asArray() -> [Any] {
        switch self {
        case .empty:
            return []
        case .single(let value):
            return [value]
        case .many(let values):
            return values
        }
    }
}

internal final class EncodeFrame {
    var object: Any?
    let undefined: Bool
    let path: KeyPathNode
    let config: EncodeConfig
    let depth: Int

    var phase: EncodePhase = .start
    var values: EncodedValuesBuffer = .empty
    var keyState: EncodeKeyState = .none
    var index: Int = 0
    var seqList: [Any]?
    var commaEffectiveLength: Int?
    var adjustedPath: KeyPathNode?
    var trackedContainerID: ObjectIdentifier?

    init(
        object: Any?,
        undefined: Bool,
        path: KeyPathNode,
        config: EncodeConfig,
        depth: Int
    ) {
        self.object = object
        self.undefined = undefined
        self.path = path
        self.config = config
        self.depth = depth
    }
}

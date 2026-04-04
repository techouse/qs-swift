import Foundation

extension Utils {
    @inline(__always)
    private static func foundationContainerID(_ value: Any) -> ObjectIdentifier? {
        guard Swift.type(of: value) is AnyClass else { return nil }
        if let dict = value as? NSDictionary {
            return ObjectIdentifier(dict)
        }
        if let array = value as? NSArray {
            return ObjectIdentifier(array)
        }
        return nil
    }

    /// Compact a nested structure by removing all `Undefined` values.
    /// - Note: `NSNull()` is preserved (represents an explicit `null`).
    /// - If `allowSparseLists` is `false` (default), `Undefined` array holes are removed
    ///   (indexes shift), while explicit `nil` remains as `NSNull()`.
    /// - If `allowSparseLists` is `true`, holes are kept as `NSNull()` (Swift arrays can't be truly sparse).
    @usableFromInline
    static func compact(
        _ root: inout [String: Any?],
        allowSparseLists: Bool = false
    ) -> [String: Any?] {
        final class DictBox {
            var dict: [String: Any?]
            init(_ capacity: Int) {
                self.dict = [:]
                self.dict.reserveCapacity(capacity)
            }
        }
        final class ArrayBox {
            var arr: [Any?]
            init(_ count: Int) { self.arr = Array(repeating: nil, count: count) }
        }

        typealias Assign = (Any?) -> Void
        enum Task {
            case build(node: Any?, assign: Assign)
            case commitDict(DictBox, ObjectIdentifier?, Assign)
            case commitArray(ArrayBox, ObjectIdentifier?, Assign)
        }

        var activeFoundationContainers: Set<ObjectIdentifier> = []
        var result: Any?
        var stack: [Task] = [.build(node: root, assign: { result = $0 })]

        @inline(__always)
        func scheduleEntries(
            _ entries: [(String, Any?)],
            foundationID: ObjectIdentifier?,
            assign: @escaping Assign
        ) {
            let box = DictBox(entries.count)
            stack.append(.commitDict(box, foundationID, assign))
            for (key, child) in entries.reversed() {
                let value = Utils.eraseOptionalLike(child)
                if value is Undefined { continue }
                if value == nil {
                    box.dict.updateValue(nil, forKey: key)
                    continue
                }
                stack.append(
                    .build(
                        node: value,
                        assign: { value in
                            box.dict.updateValue(value, forKey: key)
                        }))
            }
        }

        @inline(__always)
        func scheduleArray(
            count: Int,
            foundationID: ObjectIdentifier?,
            assign: @escaping Assign,
            visit: (@escaping (_ index: Int, _ child: Any?) -> Void) -> Void
        ) {
            let box = ArrayBox(count)
            stack.append(.commitArray(box, foundationID, assign))

            visit { index, rawElement in
                let element = Utils.eraseOptionalElement(rawElement)
                if element is Undefined {
                    if allowSparseLists {
                        box.arr[index] = NSNull()
                    }
                    return
                }
                guard let element else {
                    box.arr[index] = NSNull()
                    return
                }
                stack.append(
                    .build(
                        node: element,
                        assign: { value in
                            box.arr[index] = value
                        }))
            }
        }

        while let task = stack.popLast() {
            switch task {
            case .build(let rawNode, let assign):
                let node = Utils.eraseOptionalLike(rawNode)
                if node is Undefined {
                    assign(nil)
                    continue
                }
                guard let node else {
                    assign(nil)
                    continue
                }

                let foundationID = Utils.foundationContainerID(node)
                if let foundationID {
                    guard activeFoundationContainers.insert(foundationID).inserted else {
                        assign(NSNull())
                        continue
                    }
                }

                if Utils.withExactStringifiedEntries(
                    node,
                    { entries in
                        scheduleEntries(entries, foundationID: foundationID, assign: assign)
                    }) != nil
                {
                    continue
                }

                if Utils.withExactArrayElements(
                    node,
                    { count, visit in
                        scheduleArray(count: count, foundationID: foundationID, assign: assign, visit: visit)
                    }) != nil
                {
                    continue
                }

                assign(node)

            case .commitDict(let box, let foundationID, let assign):
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                }
                assign(box.dict)

            case .commitArray(let box, let foundationID, let assign):
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                }
                let array = allowSparseLists ? box.arr.map { $0 ?? NSNull() } : box.arr.compactMap { $0 }
                assign(array)
            }
        }

        root = result as? [String: Any?] ?? [:]
        return root
    }

    /// Remove `Undefined`, coerce optionals to concrete `Any`, keep `NSNull`,
    /// and (optionally) preserve sparse arrays with `NSNull()` placeholders.
    @usableFromInline
    static func compactToAny(
        _ root: [String: Any?],
        allowSparseLists: Bool
    ) -> [String: Any] {
        final class DictBox {
            var dict: [String: Any]
            init(_ capacity: Int) {
                self.dict = [:]
                self.dict.reserveCapacity(capacity)
            }
        }
        final class ArrayBox {
            var arr: [Any?]
            init(_ count: Int) { self.arr = Array(repeating: nil, count: count) }
        }

        typealias Assign = (Any?) -> Void
        enum Task {
            case build(node: Any?, assign: Assign)
            case commitDict(DictBox, ObjectIdentifier?, Assign)
            case commitArray(ArrayBox, ObjectIdentifier?, Assign)
        }

        var activeFoundationContainers: Set<ObjectIdentifier> = []
        var result: Any?
        var stack: [Task] = [.build(node: root, assign: { result = $0 })]

        @inline(__always)
        func scheduleEntries(
            _ entries: [(String, Any?)],
            foundationID: ObjectIdentifier?,
            assign: @escaping Assign
        ) {
            let box = DictBox(entries.count)
            stack.append(.commitDict(box, foundationID, assign))
            for (key, child) in entries.reversed() {
                stack.append(
                    .build(
                        node: child,
                        assign: { value in
                            guard let value else { return }
                            box.dict[key] = value
                        }))
            }
        }

        @inline(__always)
        func scheduleArray(
            count: Int,
            foundationID: ObjectIdentifier?,
            assign: @escaping Assign,
            visit: (@escaping (_ index: Int, _ child: Any?) -> Void) -> Void
        ) {
            let box = ArrayBox(count)
            stack.append(.commitArray(box, foundationID, assign))

            visit { index, rawElement in
                let element = Utils.eraseOptionalElement(rawElement)
                if element is Undefined {
                    if allowSparseLists {
                        box.arr[index] = NSNull()
                    }
                    return
                }
                guard let element else {
                    box.arr[index] = NSNull()
                    return
                }
                stack.append(
                    .build(
                        node: element,
                        assign: { value in
                            box.arr[index] = value
                        }))
            }
        }

        while let task = stack.popLast() {
            switch task {
            case .build(let rawNode, let assign):
                let node = Utils.eraseOptionalLike(rawNode)
                if node is Undefined {
                    assign(nil)
                    continue
                }
                guard let node else {
                    assign(NSNull())
                    continue
                }

                let foundationID = Utils.foundationContainerID(node)
                if let foundationID {
                    guard activeFoundationContainers.insert(foundationID).inserted else {
                        assign(NSNull())
                        continue
                    }
                }

                if Utils.withExactStringifiedEntries(
                    node,
                    { entries in
                        scheduleEntries(entries, foundationID: foundationID, assign: assign)
                    }) != nil
                {
                    continue
                }

                if Utils.withExactArrayElements(
                    node,
                    { count, visit in
                        scheduleArray(count: count, foundationID: foundationID, assign: assign, visit: visit)
                    }) != nil
                {
                    continue
                }

                assign(node)

            case .commitDict(let box, let foundationID, let assign):
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                }
                assign(box.dict)

            case .commitArray(let box, let foundationID, let assign):
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                }
                let array = allowSparseLists ? box.arr.map { $0 ?? NSNull() } : box.arr.compactMap { $0 }
                assign(array)
            }
        }

        return result as? [String: Any] ?? [:]
    }
}

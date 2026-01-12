import Foundation
import OrderedCollections

/// A collection of utility methods used by the library.
internal enum Utils {
    // MARK: - Non-nullish Primitive Check

    /// Checks if a value is a non-nullish primitive type. A non-nullish primitive is defined as a
    /// String, Number, Bool, enum, Date, or URL. If `skipNulls` is true, empty Strings and URLs are also considered non-nullish.
    ///
    /// - Parameters:
    ///   - value: The value to check.
    ///   - skipNulls: If true, empty Strings and URLs are not considered non-nullish.
    /// - Returns: True if the value is a non-nullish primitive, false otherwise.
    @usableFromInline
    static func isNonNullishPrimitive(_ value: Any?, skipNulls: Bool = false) -> Bool {
        switch value {
        case let string as String:
            return skipNulls ? !string.isEmpty : true
        case is NSNumber, is Bool, is Date:
            return true
        case let url as URL:
            return skipNulls ? !url.absoluteString.isEmpty : true
        case is [Any],
            is [AnyHashable: Any],
            is OrderedDictionary<String, Any>,
            is OrderedDictionary<AnyHashable, Any>,
            is NSDictionary,
            is Undefined:
            return false
        case nil:
            return false
        default:
            return true
        }
    }

    // MARK: - Is Empty Check

    /// Checks if a value is empty. A value is considered empty if it is nil, Undefined, an empty
    /// String, an empty Array, or an empty Dictionary.
    ///
    /// - Parameter value: The value to check.
    /// - Returns: True if the value is empty, false otherwise.
    @usableFromInline
    static func isEmpty(_ value: Any?) -> Bool {
        switch value {
        case nil, is Undefined:
            return true
        case let string as String:
            return string.isEmpty
        case let array as [Any]:
            return array.isEmpty
        case let od as OrderedDictionary<String, Any>:
            return od.isEmpty
        case let od as OrderedDictionary<AnyHashable, Any>:
            return od.isEmpty
        case let dict as [AnyHashable: Any]:
            return dict.isEmpty
        default:
            return false
        }
    }

    // MARK: - Deep bridge to Any WITHOUT recursion

    @inline(never)
    internal static func deepBridgeToAnyIterative(_ root: Any?) -> Any {
        final class DictBox { var dict: [String: Any] = [:] }
        final class ArrayBox {
            var arr: [Any]
            init(_ count: Int) { self.arr = Array(repeating: NSNull(), count: count) }
        }

        typealias Assign = (Any) -> Void
        enum Task {
            case build(node: Any?, assign: Assign)
            case commitDict(DictBox, Assign)
            case commitArray(ArrayBox, Assign)
        }

        var result: Any = NSNull()
        var stack: [Task] = [.build(node: root, assign: { result = $0 })]

        while let task = stack.popLast() {
            switch task {
            case let .build(node, assign):
                guard let node else {
                    assign(NSNull())
                    continue
                }

                if let dict = node as? [String: Any?] {
                    let box = DictBox()
                    stack.append(.commitDict(box, assign))
                    for (key, child) in dict {
                        stack.append(.build(node: child, assign: { value in box.dict[key] = value }))
                    }
                    continue
                }

                if let dictAHOpt = node as? [AnyHashable: Any?] {
                    let box = DictBox()
                    stack.append(.commitDict(box, assign))
                    for (keyHash, child) in dictAHOpt {
                        if Utils.isOverflowKey(keyHash) { continue }
                        let keyString = String(describing: keyHash)
                        stack.append(.build(node: child, assign: { value in box.dict[keyString] = value }))
                    }
                    continue
                }

                if let dictAH = node as? [AnyHashable: Any] {
                    let box = DictBox()
                    stack.append(.commitDict(box, assign))
                    for (keyHash, child) in dictAH {
                        if Utils.isOverflowKey(keyHash) { continue }
                        let keyString = String(describing: keyHash)
                        stack.append(.build(node: child, assign: { value in box.dict[keyString] = value }))
                    }
                    continue
                }

                if let arr = node as? [Any] {
                    let box = ArrayBox(arr.count)
                    stack.append(.commitArray(box, assign))
                    for (index, child) in arr.enumerated() {
                        stack.append(.build(node: child, assign: { value in box.arr[index] = value }))
                    }
                    continue
                }

                if let arrOpt = node as? [Any?] {
                    let box = ArrayBox(arrOpt.count)
                    stack.append(.commitArray(box, assign))
                    for (index, child) in arrOpt.enumerated() {
                        stack.append(.build(node: child, assign: { value in box.arr[index] = value }))
                    }
                    continue
                }

                assign(node)

            case let .commitDict(box, assign):
                assign(box.dict)

            case let .commitArray(box, assign):
                assign(box.arr)
            }
        }

        return result
    }

    // --- Compact only when necessary (avoid deep recursion if no Undefined) ---
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    internal static func containsUndefined(_ root: Any?) -> Bool {
        var stack: [Any?] = [root]
        while let node = stack.popLast() {
            if node is Undefined { return true }

            if let dict = node as? [String: Any?] {
                stack.append(contentsOf: dict.values)  // values are Any?
            } else if let dict = node as? [AnyHashable: Any] {
                stack.append(contentsOf: dict.values.map { Optional($0) })  // wrap Any → Any?
            } else if let array = node as? [Any?] {
                stack.append(contentsOf: array)  // already Any?
            } else if let array = node as? [Any] {
                stack.append(contentsOf: array.map { Optional($0) })  // wrap Any → Any?
            }
        }
        return false
    }

    // MARK: - Main-thread teardown & depth heuristics

    /// Very fast estimator for single-key-chain depth; caps work.
    @inline(__always)
    internal static func estimateSingleKeyChainDepth(_ value: Any?, cap: Int = 20_000) -> Int {
        var depth = 0
        var current = value
        while depth < cap {
            if let dict = current as? [String: Any?], dict.count == 1, let next = dict.first?.value {
                current = next
                depth += 1
                continue
            }
            if let dict = current as? [AnyHashable: Any?], dict.count == 1, let next = dict.first?.value {
                current = next
                depth += 1
                continue
            }
            if let dict = current as? [AnyHashable: Any], dict.count == 1, let next = dict.first?.value {
                current = next
                depth += 1
                continue
            }
            return depth
        }
        return depth
    }

    /// Decide if we should drop on main based on a quick scan of top-level values.
    /// This is cheap and catches the pathological "p→p→p..." shape.
    internal static func needsMainDrop(_ root: [String: Any?], threshold: Int) -> Bool {
        // fast exit for small graphs
        if threshold <= 0 { return false }
        for value in root.values where estimateSingleKeyChainDepth(value, cap: threshold + 1) >= threshold {
            return true
        }
        return false
    }

    /// Drop an object on the main thread, retaining it until the async block runs.
    /// This is useful for cleaning up resources that should be released on the main thread.
    @inline(__always)
    internal static func dropOnMainThread(_ obj: AnyObject?) {
        guard let obj else { return }
        let token = _RetainedToken(raw: Unmanaged.passRetained(obj))
        DispatchQueue.main.async { token.raw.release() }
    }

    // Keep the existing Any? convenience that forwards:
    @inline(__always)
    internal static func dropOnMainThread(_ payload: Any?) {
        dropOnMainThread(payload as AnyObject?)
    }
}

// A tiny wrapper so we can capture the retained token in a @Sendable closure.
private struct _RetainedToken: @unchecked Sendable {
    let raw: Unmanaged<AnyObject>
}

// A simple box to hold a payload for deferred execution on the main thread.
private final class _DropBox: @unchecked Sendable {
    var payload: Any?
    init(_ payload: Any?) { self.payload = payload }
    deinit { payload = nil }
}

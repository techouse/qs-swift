// swiftlint:disable file_length
import Foundation
import OrderedCollections

private protocol QsOptionalValue {
    var _qsWrappedAny: Any? { get }
}

extension Optional: QsOptionalValue {
    fileprivate var _qsWrappedAny: Any? {
        switch self {
        case .some(let wrapped):
            return wrapped
        case .none:
            return nil
        }
    }
}

protocol QsErasedDictionaryContainer {
    var _qsCount: Int { get }
    func _qsForEachEntry(_ body: (AnyHashable, Any?) -> Void)
    func _qsFirstEntry() -> (key: AnyHashable, value: Any?)?
}

protocol QsErasedArrayContainer {
    var _qsCount: Int { get }
    func _qsForEachElement(_ body: (Int, Any?) -> Void)
}

extension Dictionary: QsErasedDictionaryContainer where Key: Hashable {
    var _qsCount: Int { count }

    func _qsForEachEntry(_ body: (AnyHashable, Any?) -> Void) {
        for (key, value) in self {
            body(AnyHashable(key), Utils.eraseOptionalLike(value))
        }
    }

    func _qsFirstEntry() -> (key: AnyHashable, value: Any?)? {
        for (key, value) in self {
            return (AnyHashable(key), Utils.eraseOptionalLike(value))
        }
        return nil
    }
}

extension OrderedDictionary: QsErasedDictionaryContainer where Key: Hashable {
    var _qsCount: Int { count }

    func _qsForEachEntry(_ body: (AnyHashable, Any?) -> Void) {
        for (key, value) in self {
            body(AnyHashable(key), Utils.eraseOptionalLike(value))
        }
    }

    func _qsFirstEntry() -> (key: AnyHashable, value: Any?)? {
        for (key, value) in self {
            return (AnyHashable(key), Utils.eraseOptionalLike(value))
        }
        return nil
    }
}

extension Array: QsErasedArrayContainer {
    var _qsCount: Int { count }

    func _qsForEachElement(_ body: (Int, Any?) -> Void) {
        for (index, value) in enumerated() {
            body(index, Utils.eraseOptionalLike(value))
        }
    }
}

/// A collection of utility methods used by the library.
internal enum Utils {
    private final class GenericContainerTypeNameCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [ObjectIdentifier: Bool] = [:]

        @inline(__always)
        func value(for key: ObjectIdentifier) -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }

        @inline(__always)
        func set(_ value: Bool, for key: ObjectIdentifier) {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = value
        }
    }

    private static let genericContainerTypeNameCache = GenericContainerTypeNameCache()

    // MARK: - Non-nullish Primitive Check

    /// Checks if a value is a non-nullish primitive type. A non-nullish primitive is defined as a
    /// String, Number, Bool, enum, Date, or URL.
    /// When `skipNulls == true`, empty `String` and empty `URL`/`NSURL` absolute-string values
    /// are treated as null/ignored (this function returns `false` for them).
    /// When `skipNulls == false`, those empty string/URL values are considered present
    /// (this function returns `true` for them).
    ///
    /// - Parameters:
    ///   - value: The value to check.
    ///   - skipNulls: Controls empty string/URL handling (`true` => return `false`, `false` => return `true`).
    /// - Returns: True if the value is a non-nullish primitive, false otherwise.
    @usableFromInline
    static func isNonNullishPrimitive(_ value: Any?, skipNulls: Bool = false) -> Bool {
        guard let value else { return false }

        if let string = value as? String {
            return skipNulls ? !string.isEmpty : true
        }
        if value is Bool
            || value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64
            || value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64
            || value is Float || value is Double
            || value is Decimal
            || value is Date
        {
            return true
        }
        #if os(macOS) && arch(arm64)
            if #available(macOS 11, *) {
                if value is Float16 { return true }
            }
        #elseif os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 14, *) {
                if value is Float16 { return true }
            }
        #elseif os(tvOS)
            if #available(tvOS 14, *) {
                if value is Float16 { return true }
            }
        #elseif os(watchOS)
            if #available(watchOS 7, *) {
                if value is Float16 { return true }
            }
        #endif
        if let url = value as? URL {
            return skipNulls ? !url.absoluteString.isEmpty : true
        }

        if value is Undefined {
            return false
        }

        // For class-backed values, class casts are safe and avoid reflective type-name allocation.
        if Swift.type(of: value) is AnyClass {
            let object = value as AnyObject
            if object is NSDictionary || object is NSArray { return false }
            if object is NSNumber || object is NSDate { return true }
            if let nsURL = object as? NSURL {
                let urlString = nsURL.absoluteString ?? ""
                return skipNulls ? !urlString.isEmpty : true
            }
            return true
        }

        // Fast path for common native container shapes used by the encoder.
        if value is [Any]
            || value is [Any?]
            || value is [String: Any]
            || value is [AnyHashable: Any]
            || value is OrderedDictionary<String, Any>
            || value is OrderedDictionary<AnyHashable, Any>
        {
            return false
        }

        // Fallback for uncommon generic container payloads without eager value bridging.
        if isGenericContainerTypeByName(value) {
            return false
        }

        return true
    }

    @inline(__always)
    private static func isGenericContainerTypeByName(_ value: Any) -> Bool {
        let runtimeType = Swift.type(of: value)
        let cacheKey = ObjectIdentifier(runtimeType)

        if let cached = genericContainerTypeNameCache.value(for: cacheKey) {
            return cached
        }

        let typeName = String(reflecting: runtimeType)
        let isGenericContainerType: Bool = {
            guard let genericStart = typeName.firstIndex(of: "<") else { return false }
            let qualifiedTypeName = typeName[..<genericStart]
            let typeBaseName: Substring
            if let lastDot = qualifiedTypeName.lastIndex(of: ".") {
                typeBaseName = qualifiedTypeName[qualifiedTypeName.index(after: lastDot)...]
            } else {
                typeBaseName = qualifiedTypeName
            }

            return typeBaseName == "Dictionary"
                || typeBaseName == "OrderedDictionary"
                || typeBaseName == "Array"
        }()

        genericContainerTypeNameCache.set(isGenericContainerType, for: cacheKey)
        return isGenericContainerType
    }

    // Avoid downcasting between `[String: Any]` and `[String: Any?]` (and the array/hashable
    // equivalents) while traversing deep graphs. Swift 6.3 can recursively walk the entire
    // subtree for those conversions, which overflows worker-thread stacks on long chains.
    private enum ExactContainer {
        case stringAny([String: Any])
        case stringOptional([String: Any?])
        case anyHashableAny([AnyHashable: Any])
        case anyHashableOptional([AnyHashable: Any?])
        case arrayAny([Any])
        case arrayOptional([Any?])
        case foundationDictionary(NSDictionary)
        case foundationArray(NSArray)
        case genericDictionary(any QsErasedDictionaryContainer)
        case genericArray(any QsErasedArrayContainer)
    }

    @inline(__always)
    static func eraseOptionalLike<T>(_ value: T) -> Any? {
        if let optional = value as? QsOptionalValue {
            return optional._qsWrappedAny
        }
        return value
    }

    @inline(__always)
    private static func exactContainer(_ value: Any) -> ExactContainer? {
        let valueType = Swift.type(of: value)

        @inline(__always)
        func exactCast<T>(_ type: T.Type) -> T? {
            guard valueType == type else { return nil }
            guard let typed = value as? T else {
                assertionFailure("Exact cast failed for runtime type \(valueType)")
                return nil
            }
            return typed
        }

        if let dict = exactCast([String: Any].self) {
            return .stringAny(dict)
        }
        if let dict = exactCast([String: Any?].self) {
            return .stringOptional(dict)
        }
        if let dict = exactCast([AnyHashable: Any].self) {
            return .anyHashableAny(dict)
        }
        if let dict = exactCast([AnyHashable: Any?].self) {
            return .anyHashableOptional(dict)
        }
        if let array = exactCast([Any].self) {
            return .arrayAny(array)
        }
        if let array = exactCast([Any?].self) {
            return .arrayOptional(array)
        }
        if valueType is AnyClass, let dict = value as? NSDictionary {
            return .foundationDictionary(dict)
        }
        if valueType is AnyClass, let array = value as? NSArray {
            return .foundationArray(array)
        }
        if let dict = value as? any QsErasedDictionaryContainer {
            return .genericDictionary(dict)
        }
        if let array = value as? any QsErasedArrayContainer {
            return .genericArray(array)
        }

        return nil
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
        final class DictBox {
            var dict: [String: Any]
            init(_ capacity: Int) {
                self.dict = [:]
                self.dict.reserveCapacity(capacity)
            }
        }
        final class ArrayBox {
            var arr: [Any]
            init(_ count: Int) { self.arr = Array(repeating: NSNull(), count: count) }
        }

        typealias Assign = (Any) -> Void
        enum Task {
            case build(node: Any?, assign: Assign)
            case commitDict(DictBox, ObjectIdentifier?, Assign)
            case commitArray(ArrayBox, ObjectIdentifier?, Assign)
        }

        var result: Any = NSNull()
        var stack: [Task] = [.build(node: root, assign: { result = $0 })]
        var activeFoundationContainers: Set<ObjectIdentifier> = []
        var completedFoundationContainers: [ObjectIdentifier: Any] = [:]

        @inline(__always)
        func scheduleDictionaryEntries(
            _ entries: [(String, Any?)],
            assign: @escaping Assign,
            foundationID: ObjectIdentifier? = nil
        ) {
            let box = DictBox(entries.count)
            stack.append(.commitDict(box, foundationID, assign))
            for (key, child) in entries.reversed() {
                stack.append(.build(node: child, assign: { value in box.dict[key] = value }))
            }
        }

        @inline(__always)
        func scheduleStringDictionary<Value>(
            _ dict: [String: Value],
            assign: @escaping Assign
        ) {
            var entries: [(String, Any?)] = []
            entries.reserveCapacity(dict.count)
            for (key, child) in dict {
                entries.append((key, Utils.eraseOptionalLike(child)))
            }
            scheduleDictionaryEntries(entries, assign: assign)
        }

        @inline(__always)
        func scheduleAnyHashableDictionary<Value>(
            _ dict: [AnyHashable: Value],
            assign: @escaping Assign
        ) {
            var entries: [(String, Any?)] = []
            entries.reserveCapacity(dict.count)
            for (keyHash, child) in dict {
                if Utils.isOverflowKey(keyHash) { continue }
                entries.append((String(describing: keyHash), Utils.eraseOptionalLike(child)))
            }
            scheduleDictionaryEntries(entries, assign: assign)
        }

        @inline(__always)
        func scheduleFoundationDictionary(
            _ dict: NSDictionary,
            assign: @escaping Assign
        ) {
            let foundationID = ObjectIdentifier(dict)
            if let cached = completedFoundationContainers[foundationID] {
                assign(cached)
                return
            }
            guard activeFoundationContainers.insert(foundationID).inserted else {
                assign(NSNull())
                return
            }

            var entries: [(String, Any?)] = []
            entries.reserveCapacity(dict.count)
            for (key, child) in dict {
                if let keyHash = key as? AnyHashable, Utils.isOverflowKey(keyHash) { continue }
                entries.append((String(describing: key), child))
            }
            scheduleDictionaryEntries(entries, assign: assign, foundationID: foundationID)
        }

        @inline(__always)
        func scheduleFoundationArray(
            _ array: NSArray,
            assign: @escaping Assign
        ) {
            let foundationID = ObjectIdentifier(array)
            if let cached = completedFoundationContainers[foundationID] {
                assign(cached)
                return
            }
            guard activeFoundationContainers.insert(foundationID).inserted else {
                assign(NSNull())
                return
            }

            let box = ArrayBox(array.count)
            stack.append(.commitArray(box, foundationID, assign))
            for (index, child) in array.enumerated() {
                stack.append(.build(node: child, assign: { value in box.arr[index] = value }))
            }
        }

        while let task = stack.popLast() {
            switch task {
            case .build(let node, let assign):
                guard let node else {
                    assign(NSNull())
                    continue
                }

                switch exactContainer(node) {
                case .stringOptional(let dict):
                    scheduleStringDictionary(dict, assign: assign)
                    continue
                case .stringAny(let dict):
                    scheduleStringDictionary(dict, assign: assign)
                    continue
                case .anyHashableOptional(let dictAHOpt):
                    scheduleAnyHashableDictionary(dictAHOpt, assign: assign)
                    continue
                case .anyHashableAny(let dictAH):
                    scheduleAnyHashableDictionary(dictAH, assign: assign)
                    continue
                case .arrayAny(let arr):
                    let box = ArrayBox(arr.count)
                    stack.append(.commitArray(box, nil, assign))
                    for (index, child) in arr.enumerated() {
                        stack.append(.build(node: child, assign: { value in box.arr[index] = value }))
                    }
                    continue
                case .arrayOptional(let arrOpt):
                    let box = ArrayBox(arrOpt.count)
                    stack.append(.commitArray(box, nil, assign))
                    for (index, child) in arrOpt.enumerated() {
                        stack.append(.build(node: child, assign: { value in box.arr[index] = value }))
                    }
                    continue
                case .foundationDictionary(let dict):
                    scheduleFoundationDictionary(dict, assign: assign)
                    continue
                case .foundationArray(let array):
                    scheduleFoundationArray(array, assign: assign)
                    continue
                case .genericDictionary(let dict):
                    var entries: [(String, Any?)] = []
                    entries.reserveCapacity(dict._qsCount)
                    dict._qsForEachEntry { keyHash, child in
                        if Utils.isOverflowKey(keyHash) { return }
                        entries.append((String(describing: keyHash), child))
                    }
                    scheduleDictionaryEntries(entries, assign: assign)
                    continue
                case .genericArray(let array):
                    let box = ArrayBox(array._qsCount)
                    stack.append(.commitArray(box, nil, assign))
                    array._qsForEachElement { index, child in
                        stack.append(.build(node: child, assign: { value in box.arr[index] = value }))
                    }
                    continue
                case nil:
                    break
                }

                assign(node)

            case .commitDict(let box, let foundationID, let assign):
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                    completedFoundationContainers[foundationID] = box.dict
                }
                assign(box.dict)

            case .commitArray(let box, let foundationID, let assign):
                if let foundationID {
                    activeFoundationContainers.remove(foundationID)
                    completedFoundationContainers[foundationID] = box.arr
                }
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
        var visitedFoundationContainers: Set<ObjectIdentifier> = []
        while let node = stack.popLast() {
            if node is Undefined { return true }
            guard let node else { continue }

            switch exactContainer(node) {
            case .stringOptional(let dict):
                stack.append(contentsOf: dict.values)
            case .stringAny(let dict):
                stack.reserveCapacity(stack.count + dict.count)
                for child in dict.values { stack.append(child) }
            case .anyHashableOptional(let dict):
                stack.append(contentsOf: dict.values)
            case .anyHashableAny(let dict):
                stack.reserveCapacity(stack.count + dict.count)
                for child in dict.values { stack.append(child) }
            case .arrayOptional(let array):
                stack.append(contentsOf: array)
            case .arrayAny(let array):
                stack.reserveCapacity(stack.count + array.count)
                for child in array { stack.append(child) }
            case .foundationDictionary(let dict):
                guard visitedFoundationContainers.insert(ObjectIdentifier(dict)).inserted else { continue }
                stack.reserveCapacity(stack.count + dict.count)
                for (_, child) in dict { stack.append(child) }
            case .foundationArray(let array):
                guard visitedFoundationContainers.insert(ObjectIdentifier(array)).inserted else { continue }
                stack.reserveCapacity(stack.count + array.count)
                for child in array { stack.append(child) }
            case .genericDictionary(let dict):
                stack.reserveCapacity(stack.count + dict._qsCount)
                dict._qsForEachEntry { _, child in stack.append(child) }
            case .genericArray(let array):
                stack.reserveCapacity(stack.count + array._qsCount)
                array._qsForEachElement { _, child in stack.append(child) }
            case nil:
                break
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
            guard let currentValue = current else { return depth }

            switch exactContainer(currentValue) {
            case .stringOptional(let dict):
                guard dict.count == 1, let entry = dict.first else { return depth }
                current = entry.value
            case .stringAny(let dict):
                guard dict.count == 1, let next = dict.first?.value else { return depth }
                current = next
            case .anyHashableOptional(let dict):
                guard dict.count == 1, let entry = dict.first else { return depth }
                current = entry.value
            case .anyHashableAny(let dict):
                guard dict.count == 1, let next = dict.first?.value else { return depth }
                current = next
            case .foundationDictionary(let dict):
                guard dict.count == 1, let next = dict.objectEnumerator().nextObject() else { return depth }
                current = next
            case .genericDictionary(let dict):
                guard dict._qsCount == 1, let entry = dict._qsFirstEntry() else { return depth }
                current = entry.value
            case .arrayAny, .arrayOptional, .foundationArray, .genericArray, nil:
                return depth
            }
            depth += 1
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

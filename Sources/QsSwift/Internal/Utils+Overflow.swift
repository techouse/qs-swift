import Foundation

extension Utils {
    internal struct OverflowKey: Hashable, Sendable {}

    @usableFromInline
    internal static let overflowKey = OverflowKey()

    @inline(__always)
    @usableFromInline
    internal static func intIndex(_ key: AnyHashable) -> Int? {
        if let intValue = key.base as? Int { return intValue }
        if let number = key.base as? NSNumber { return number.intValue }
        return nil
    }

    @usableFromInline
    internal static func isOverflow(_ value: Any?) -> Bool {
        guard let dict = value as? [AnyHashable: Any] else { return false }
        return dict[AnyHashable(overflowKey)] is Int
    }

    @usableFromInline
    internal static func overflowMaxIndex(_ dict: [AnyHashable: Any]) -> Int? {
        dict[AnyHashable(overflowKey)] as? Int
    }

    @usableFromInline
    internal static func setOverflowMaxIndex(_ dict: inout [AnyHashable: Any], _ maxIndex: Int) {
        dict[overflowKey] = maxIndex
    }

    @usableFromInline
    internal static func markOverflow(
        _ dict: [AnyHashable: Any],
        maxIndex: Int
    ) -> [AnyHashable: Any] {
        var copy = dict
        copy[overflowKey] = maxIndex
        return copy
    }

    @usableFromInline
    internal static func isOverflowKey(_ key: AnyHashable) -> Bool {
        key == AnyHashable(overflowKey)
    }

    @usableFromInline
    internal static func refreshOverflowMaxIndex(_ dict: inout [AnyHashable: Any]) {
        var maxIndex = -1
        for key in dict.keys where !isOverflowKey(key) {
            if let idx = intIndex(key), idx > maxIndex {
                maxIndex = idx
            }
        }
        setOverflowMaxIndex(&dict, maxIndex)
    }
}

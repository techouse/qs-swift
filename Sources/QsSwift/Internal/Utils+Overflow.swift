import Foundation

extension Utils {
    internal struct OverflowKey: Hashable, Sendable {}

    @usableFromInline
    internal static let overflowKey = OverflowKey()

    @usableFromInline
    internal static let maximumSafeJavaScriptInteger = 9_007_199_254_740_991

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
        return dict[overflowKey] is Int
    }

    @usableFromInline
    internal static func overflowMaxIndex(_ dict: [AnyHashable: Any]) -> Int? {
        dict[overflowKey] as? Int
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
        key.base is OverflowKey
    }

    @inline(__always)
    @usableFromInline
    internal static func nextOverflowIndex(after index: Int) -> Int? {
        if index <= maximumSafeJavaScriptInteger { return index + 1 }
        // qs advances overflow keys with JavaScript Number arithmetic, including
        // its rounding behavior above Number.MAX_SAFE_INTEGER.
        let next = Double(index) + 1
        return next.isFinite ? Int(javascriptIntegerDescription(next)) : nil
    }

    /// Expands Swift's shortest `Double` description to JavaScript's fixed integer form.
    @usableFromInline
    internal static func javascriptIntegerDescription(_ value: Double) -> String {
        let description = String(value)
        guard let exponentIndex = description.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return description.hasSuffix(".0") ? String(description.dropLast(2)) : description
        }

        let mantissa = description[..<exponentIndex]
        let exponentStart = description.index(after: exponentIndex)
        guard let exponent = Int(description[exponentStart...]) else { return description }

        let components = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = components.first else { return description }
        let fraction = components.count == 2 ? components[1] : Substring()
        let zeroCount = exponent - fraction.count
        guard zeroCount >= 0 else { return description }
        return String(whole) + String(fraction) + String(repeating: "0", count: zeroCount)
    }

    @usableFromInline
    internal static func removingOverflowMetadata(
        from dict: [AnyHashable: Any]
    ) -> [AnyHashable: Any] {
        var copy = dict
        copy.removeValue(forKey: overflowKey)
        return copy
    }

    @usableFromInline
    /// Scans non-overflow keys to compute the maximum integer index and stores it.
    /// Sets -1 if no integer keys are present.
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

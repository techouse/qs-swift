import Foundation
import OrderedCollections

/// Holds pre-scanned key-shape information for decode fast-path routing.
@usableFromInline
internal struct StructuredKeyScan: Sendable {
    @usableFromInline
    internal static let empty = StructuredKeyScan(
        hasAnyStructuredSyntax: false,
        structuredRoots: nil,
        structuredKeys: nil
    )

    @usableFromInline
    internal let hasAnyStructuredSyntax: Bool

    @usableFromInline
    internal let structuredRoots: Set<String>?

    @usableFromInline
    internal let structuredKeys: Set<String>?

    @inline(__always)
    @usableFromInline
    internal func containsStructuredRoot(_ key: String) -> Bool {
        structuredRoots?.contains(key) ?? false
    }

    @inline(__always)
    @usableFromInline
    internal func containsStructuredKey(_ key: String) -> Bool {
        structuredKeys?.contains(key) ?? false
    }
}

extension QsSwift.Decoder {
    /// Pre-scans parsed keys to detect structured syntax and conflicting roots.
    @usableFromInline
    internal static func scanStructuredKeys(
        _ tempObj: OrderedDictionary<String, Any>,
        options: DecodeOptions
    ) -> StructuredKeyScan {
        if tempObj.isEmpty { return .empty }

        let allowDots = options.getAllowDots
        var structuredRoots: Set<String>?
        var structuredKeys: Set<String>?

        for key in tempObj.keys {
            let splitAt = firstStructuredSplitIndex(key, allowDots: allowDots)
            if splitAt < 0 { continue }

            if structuredRoots == nil { structuredRoots = [] }
            if structuredKeys == nil { structuredKeys = [] }
            structuredKeys?.insert(key)

            if splitAt == 0 {
                structuredRoots?.insert(leadingStructuredRoot(key, options: options))
            } else {
                structuredRoots?.insert(String(key.prefix(splitAt)))
            }
        }

        if structuredKeys == nil { return .empty }
        return StructuredKeyScan(
            hasAnyStructuredSyntax: true,
            structuredRoots: structuredRoots,
            structuredKeys: structuredKeys
        )
    }

    /// Returns the earliest index that indicates structured key syntax.
    @usableFromInline
    internal static func firstStructuredSplitIndex(_ key: String, allowDots: Bool) -> Int {
        var splitAt = -1

        if let bracket = key.firstIndex(of: "[") {
            splitAt = key.distance(from: key.startIndex, to: bracket)
        }

        guard allowDots else { return splitAt }

        if let dot = key.firstIndex(of: ".") {
            let dotIdx = key.distance(from: key.startIndex, to: dot)
            if splitAt < 0 || dotIdx < splitAt { splitAt = dotIdx }
        }

        let encodedDotIdx = encodedDotSplitIndex(key)
        if encodedDotIdx >= 0 && (splitAt < 0 || encodedDotIdx < splitAt) {
            splitAt = encodedDotIdx
        }

        return splitAt
    }

    /// Extracts root key for leading-bracket structured keys (`[]` maps to `"0"`).
    @usableFromInline
    internal static func leadingStructuredRoot(
        _ key: String,
        options: DecodeOptions
    ) -> String {
        let segments =
            (try? splitKeyIntoSegments(
                originalKey: key,
                allowDots: options.getAllowDots,
                maxDepth: options.depth,
                strictDepth: false
            )) ?? [key]

        guard let first = segments.first else { return key }
        guard first.hasPrefix("[") else { return first }

        let cleanRoot: String = {
            if let last = first.lastIndex(of: "]"), last > first.startIndex {
                return String(first[first.index(after: first.startIndex)..<last])
            }
            return String(first.dropFirst())
        }()

        return cleanRoot.isEmpty ? "0" : cleanRoot
    }

    @inline(__always)
    private static func encodedDotSplitIndex(_ key: String) -> Int {
        if !key.contains("%") { return -1 }

        var encodedDotIdx = Int.max
        if let upper = key.range(of: "%2E") {
            encodedDotIdx = min(encodedDotIdx, key.distance(from: key.startIndex, to: upper.lowerBound))
        }
        if let lower = key.range(of: "%2e") {
            encodedDotIdx = min(encodedDotIdx, key.distance(from: key.startIndex, to: lower.lowerBound))
        }

        return encodedDotIdx == Int.max ? -1 : encodedDotIdx
    }
}

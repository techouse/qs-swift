import Foundation

/// Linked-node representation of an encoder key path.
///
/// Nodes are structurally immutable; cached views are memoized for fast reuse
/// during iterative traversal.
internal final class KeyPathNode {
    private let parent: KeyPathNode?
    private let segment: String
    private let depth: Int
    private let totalLength: Int

    private var dotEncoded: KeyPathNode?
    private var dotEncodedIsSelf = false
    private var materialized: String?

    private init(parent: KeyPathNode?, segment: String) {
        self.parent = parent
        self.segment = segment
        self.depth = (parent?.depth ?? 0) + 1
        self.totalLength = (parent?.totalLength ?? 0) + segment.count
    }

    static func fromMaterialized(_ value: String) -> KeyPathNode {
        KeyPathNode(parent: nil, segment: value)
    }

    func append(_ value: String) -> KeyPathNode {
        value.isEmpty ? self : KeyPathNode(parent: self, segment: value)
    }

    func asDotEncoded() -> KeyPathNode {
        if dotEncodedIsSelf {
            return self
        }

        if let dotEncoded {
            return dotEncoded
        }

        let encodedSegment = Self.replaceDots(in: segment)

        let encoded: KeyPathNode
        if let parent {
            let encodedParent = parent.asDotEncoded()
            if encodedParent === parent && encodedSegment == segment {
                encoded = self
            } else {
                encoded = KeyPathNode(parent: encodedParent, segment: encodedSegment)
            }
        } else if encodedSegment == segment {
            encoded = self
        } else {
            encoded = KeyPathNode(parent: nil, segment: encodedSegment)
        }

        if encoded === self {
            dotEncodedIsSelf = true
        } else {
            dotEncoded = encoded
        }
        return encoded
    }

    func materialize() -> String {
        if let materialized {
            return materialized
        }

        if parent == nil {
            materialized = segment
            return segment
        }

        if depth == 2, let parent {
            let value = parent.segment + segment
            materialized = value
            return value
        }

        var parts = Array(repeating: "", count: depth)
        var index = depth - 1
        var node: KeyPathNode? = self
        while let current = node {
            parts[index] = current.segment
            index -= 1
            node = current.parent
        }

        var out = String()
        out.reserveCapacity(totalLength)
        for part in parts {
            out.append(part)
        }

        materialized = out
        return out
    }

    private static func replaceDots(in value: String) -> String {
        value.contains(".") ? value.replacingOccurrences(of: ".", with: "%2E") : value
    }
}

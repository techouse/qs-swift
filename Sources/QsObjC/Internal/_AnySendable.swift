import Foundation

/// Generic box to carry non-Sendable values across @Sendable closures.
internal final class _AnySendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

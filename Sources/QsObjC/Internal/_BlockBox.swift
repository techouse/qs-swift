import Foundation

/// Lets us capture ObjC blocks inside @Sendable Swift closures without warnings.
internal final class _BlockBox<T>: @unchecked Sendable {
    let block: T
    init(_ block: T) { self.block = block }
}

import Foundation
import QsSwift

@objc(QsFunctionFilter)
@objcMembers
public final class FunctionFilterObjC: NSObject {
    public typealias Block = (NSString, Any?) -> Any?
    private let block: Block

    public init(_ block: @escaping Block) { self.block = block }

    public var swift: QsSwift.FunctionFilter {
        QsSwift.FunctionFilter { key, value in
            let out = self.block(key as NSString, value)
            // Map ObjC sentinel → Swift sentinel to DROP the key entirely
            if let u = out as? UndefinedObjC { return u.swift }
            return out
        }
    }
}

@objc(QsIterableFilter)
@objcMembers
public final class IterableFilterObjC: NSObject {
    public let iterable: [Any]
    public init(iterable: [Any]) { self.iterable = iterable }
    public convenience init(keys: [String]) { self.init(iterable: keys) }
    public convenience init(indices: [Int]) { self.init(iterable: indices) }
    public var swift: QsSwift.IterableFilter { QsSwift.IterableFilter(iterable) }
}

@objc(QsFilter)
@objcMembers
public final class FilterObjC: NSObject {
    private enum Backing {
        case function(QsSwift.FunctionFilter)
        case iterable(QsSwift.IterableFilter)
    }
    private let backing: Backing
    private init(_ b: Backing) { self.backing = b }

    // Factories
    public static func function(_ f: FunctionFilterObjC) -> FilterObjC { FilterObjC(.function(f.swift)) }
    public static func iterable(_ f: IterableFilterObjC) -> FilterObjC { FilterObjC(.iterable(f.swift)) }

    // Convenience helpers
    public static func excluding(_ shouldExclude: @escaping (String) -> Bool) -> FilterObjC {
        // Use sentinel to omit
        let f = QsSwift.FunctionFilter { key, value in
            shouldExclude(key) ? QsSwift.Undefined() : value
        }
        return FilterObjC(.function(f))
    }

    public static func including(_ shouldInclude: @escaping (String) -> Bool) -> FilterObjC {
        let f = QsSwift.FunctionFilter { key, value in
            shouldInclude(key) ? value : QsSwift.Undefined()
        }
        return FilterObjC(.function(f))
    }

    public static func keys(_ keys: [String]) -> FilterObjC {
        FilterObjC(.iterable(QsSwift.IterableFilter(keys)))
    }
    public static func indices(_ indices: [Int]) -> FilterObjC {
        FilterObjC(.iterable(QsSwift.IterableFilter(indices)))
    }
    public static func mixed(_ items: [Any]) -> FilterObjC {
        FilterObjC(.iterable(QsSwift.IterableFilter(items)))
    }

    // Bridge to Swift
    var swift: QsSwift.Filter {
        switch backing {
        case .function(let f): return f
        case .iterable(let i): return i
        }
    }
}

#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    // MARK: - Function-style filter

    /// Objective-C wrapper for a Swift `FunctionFilter`.
    ///
    /// Use this when you want to decide per-key whether to include, transform,
    /// or drop a key/value pair at encode time.
    ///
    /// - You receive the **raw key** (already flattened by the encoder during traversal)
    ///   and the **value** for that key.
    /// - Return the value you want to encode, or return the Obj-C sentinel
    ///   `UndefinedObjC()` to **omit the key entirely**.
    /// - Any other return value is forwarded as-is to the Swift encoder.
    ///
    /// Example (Obj-C):
    /// ```objc
    /// QsFunctionFilter *ff = [[QsFunctionFilter alloc] init:^id(NSString *key, id value) {
    ///   if ([key isEqualToString:@"password"]) { return [QsUndefined new]; } // drop
    ///   return value; // keep
    /// }];
    /// QsFilter *filter = [QsFilter function:ff];
    /// ```
    @objc(QsFunctionFilter)
    @objcMembers
    public final class FunctionFilterObjC: NSObject {
        /// Obj-C compatible block type: return `UndefinedObjC` to omit a key.
        public typealias Block = (NSString, Any?) -> Any?

        private let block: Block

        /// Create a function filter from an Objective-C block.
        public init(_ block: @escaping Block) { self.block = block }

        /// Bridge to the Swift core representation.
        public var swift: QsSwift.FunctionFilter {
            QsSwift.FunctionFilter { key, value in
                let out = self.block(key as NSString, value)
                // Map Obj-C sentinel → Swift sentinel to DROP the key entirely.
                if let undefinedObjC = out as? UndefinedObjC { return undefinedObjC.swift }
                // If Obj-C returns the same bridged object we passed in (common "return value;"
                // pattern), keep the original Swift payload to preserve container traversal.
                if let outObj = out as AnyObject?,
                    let inObj = value as AnyObject?,
                    outObj === inObj
                {
                    return value
                }
                guard let out else { return nil }
                // Normalize Obj-C containers and Undefined in one traversal.
                return QsBridge.bridgeInputForEncode(out, bridgeUndefined: true)
            }
        }
    }

    // MARK: - Iterable-style filter

    /// Objective-C wrapper for a Swift `IterableFilter`.
    ///
    /// Use this when you want to filter by **a fixed set of keys or indices**.
    /// For example, pass an array of `"name"`, `"email"` to encode only those keys,
    /// or `[0, 2]` to encode only certain array indices.
    @objc(QsIterableFilter)
    @objcMembers
    public final class IterableFilterObjC: NSObject {
        public let iterable: [Any]

        /// Create with a mixed list of items (strings and/or numbers).
        public init(iterable: [Any]) { self.iterable = iterable }

        /// Convenience: keys-only.
        public convenience init(keys: [String]) { self.init(iterable: keys) }

        /// Convenience: indices-only.
        public convenience init(indices: [Int]) { self.init(iterable: indices) }

        /// Bridge to the Swift core representation.
        public var swift: QsSwift.IterableFilter { QsSwift.IterableFilter(iterable) }
    }

    // MARK: - Unified Filter (sum type)

    /// Objective-C facade over Swift `Filter`, which can be either:
    /// - a **function** filter (`FunctionFilter`), or
    /// - an **iterable** filter (`IterableFilter`).
    ///
    /// This lets you configure filters from Obj-C in a single, type-safe API.
    @objc(QsFilter)
    @objcMembers
    public final class FilterObjC: NSObject {
        private enum Backing {
            case function(QsSwift.FunctionFilter)
            case iterable(QsSwift.IterableFilter)
        }

        private let backing: Backing
        private init(_ backing: Backing) { self.backing = backing }

        // MARK: Factories

        /// Wrap a function-style filter.
        public static func function(_ functionFilter: FunctionFilterObjC) -> FilterObjC {
            FilterObjC(.function(functionFilter.swift))
        }

        /// Wrap an iterable-style filter.
        public static func iterable(_ iterableFilter: IterableFilterObjC) -> FilterObjC {
            FilterObjC(.iterable(iterableFilter.swift))
        }

        // MARK: - Convenience builders

        /// Build a function filter that **excludes** keys for which `shouldExclude` returns true.
        /// Implementation uses the `Undefined` sentinel to omit excluded keys.
        public static func excluding(_ shouldExclude: @escaping (String) -> Bool) -> FilterObjC {
            let functionFilter = QsSwift.FunctionFilter { key, value in
                shouldExclude(key) ? QsSwift.Undefined() : value
            }
            return FilterObjC(.function(functionFilter))
        }

        /// Build a function filter that **includes only** keys for which `shouldInclude` returns true.
        /// All other keys are omitted via the `Undefined` sentinel.
        public static func including(_ shouldInclude: @escaping (String) -> Bool) -> FilterObjC {
            let functionFilter = QsSwift.FunctionFilter { key, value in
                shouldInclude(key) ? value : QsSwift.Undefined()
            }
            return FilterObjC(.function(functionFilter))
        }

        /// Convenience: allow only these keys (iterable filter).
        public static func keys(_ keys: [String]) -> FilterObjC {
            FilterObjC(.iterable(QsSwift.IterableFilter(keys)))
        }

        /// Convenience: allow only these list indices (iterable filter).
        public static func indices(_ indices: [Int]) -> FilterObjC {
            FilterObjC(.iterable(QsSwift.IterableFilter(indices)))
        }

        /// Convenience: allow a **mixed** list of keys and indices.
        public static func mixed(_ items: [Any]) -> FilterObjC {
            FilterObjC(.iterable(QsSwift.IterableFilter(items)))
        }

        // MARK: - Bridge to Swift

        /// Expose the underlying Swift `Filter` for the encoder.
        var swift: QsSwift.Filter {
            switch backing {
            case .function(let functionFilter): return functionFilter
            case .iterable(let iterableFilter): return iterableFilter
            }
        }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

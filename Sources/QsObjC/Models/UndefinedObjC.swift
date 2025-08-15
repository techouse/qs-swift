#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Objective-C bridge for the Swift `Undefined` sentinel.
    ///
    /// `Undefined` is a special marker the encoder understands as **“omit this key entirely.”**
    /// You typically return it from a `QsFunctionFilter` block when you want to drop a key/value
    /// during encoding.
    ///
    /// - Important: This is **not** a string like `"undefined"`; it’s a sentinel value.
    /// - Thread-safety: This class is stateless and safe to create/use from any thread.
    /// - Lifetime: You may create new instances as needed; all instances map to the same Swift
    ///   singleton (`QsSwift.Undefined.instance`).
    ///
    /// ### Example (Objective-C)
    /// ```objc
    /// QsFunctionFilter *ff = [[QsFunctionFilter alloc] init:^id(NSString *key, id value) {
    ///   // Hide secrets:
    ///   if ([key isEqualToString:@"password"]) { return [QsUndefined new]; } // drop
    ///   return value; // keep
    /// }];
    /// QsFilter *filter = [QsFilter function:ff];
    /// ```
    ///
    /// You can also place `QsUndefined` directly inside your data structure to omit specific keys,
    /// though using a filter is often clearer.
    @objc(QsUndefined)
    @objcMembers
    public final class UndefinedObjC: NSObject, Sendable {
        /// Create a new Obj-C sentinel instance.
        /// Multiple instances are fine; they all bridge to the same Swift singleton.
        public override init() { super.init() }

        /// Bridge to the Swift sentinel (`QsSwift.Undefined.instance`).
        ///
        /// This is used internally by the bridge and by `QsFunctionFilter` to signal omission.
        var swift: QsSwift.Undefined { .instance }
    }
#endif  // canImport(ObjectiveC) && QS_OBJC_BRIDGE

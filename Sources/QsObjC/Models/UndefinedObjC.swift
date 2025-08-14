import Foundation
import QsSwift

/// Bridges to the Swift `Undefined` sentinel used by FunctionFilter to omit keys.
@objc(QsUndefined)
@objcMembers
public final class UndefinedObjC: NSObject, Sendable {
    public override init() { super.init() }

    var swift: QsSwift.Undefined { .instance }
}

import Foundation
import QsSwift

@objc(QsUndefined)
@objcMembers
public final class UndefinedObjC: NSObject, Sendable {
    public override init() { super.init() }

    var swift: QsSwift.Undefined { .instance }
}

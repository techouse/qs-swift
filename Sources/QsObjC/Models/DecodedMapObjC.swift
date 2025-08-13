import Foundation
import QsSwift

@objc(QsDecodedMap)
@objcMembers
public final class DecodedMapObjC: NSObject {
    public let value: NSDictionary

    public init(_ dict: NSDictionary) {
        self.value = dict
    }

    public convenience init(swift: QsSwift.DecodedMap) {
        self.init(swift.value as NSDictionary)
    }

    /// Safe because every `DecodedMap` is created from a `[String: Any]` inside the core.
    var swift: QsSwift.DecodedMap { QsSwift.DecodedMap(value as! [String: Any]) }
}

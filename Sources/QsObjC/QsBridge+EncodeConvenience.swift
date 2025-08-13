import Foundation
import QsSwift

@objc extension QsBridge {
    // If your bridge helper is `private`, make it `internal static`
    // so we can call it here from another file.
    // internal static func bridgeInputForEncode(_ input: Any) -> Any { ... }

    // MARK: - ObjC-friendly encode conveniences

    @objc(encodeOrNil:)
    public static func encodeOrNil(_ data: Any?) -> NSString? {
        encodeOrNil(data, options: nil)
    }

    @objc(encodeOrNil:options:)
    public static func encodeOrNil(_ data: Any?, options: EncodeOptionsObjC?) -> NSString? {
        // Map the optional; when data is nil we call the Swift helper with nil (which returns "")
        let bridged: Any? = data.map { QsBridge.bridgeInputForEncode($0) }
        let s = Qs.encodeOrNil(bridged, options: options?.swift ?? .init())
        return s.map(NSString.init)
    }

    @objc(encodeOrEmpty:)
    public static func encodeOrEmpty(_ data: Any?) -> NSString {
        encodeOrEmpty(data, options: nil)
    }

    @objc(encodeOrEmpty:options:)
    public static func encodeOrEmpty(_ data: Any?, options: EncodeOptionsObjC?) -> NSString {
        // Mirrors Swift’s behavior: nil input is not an error → returns ""
        let bridged: Any? = data.map { QsBridge.bridgeInputForEncode($0) }
        let s = Qs.encodeOrEmpty(bridged, options: options?.swift ?? .init())
        return NSString(string: s)
    }
}

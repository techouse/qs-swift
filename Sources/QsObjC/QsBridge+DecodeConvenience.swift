import Foundation
import QsSwift

@objc extension QsBridge {
    // MARK: - ObjC-friendly: non-throwing decode helpers

    /// Returns nil only if decoding *throws*. `nil` input yields an **empty dictionary**.
    @objc(decodeOrNil:)
    public static func decodeOrNil(_ input: Any?) -> NSDictionary? {
        decodeOrNil(input, options: nil)
    }

    /// Returns nil only if decoding *throws*. `nil` input yields an **empty dictionary**.
    @objc(decodeOrNil:options:)
    public static func decodeOrNil(_ input: Any?, options: DecodeOptionsObjC?) -> NSDictionary? {
        let bridged = bridgeInputForDecode(input)
        let swiftOpts = options?.swift ?? .init()
        if let dict = Qs.decodeOrNil(bridged, options: swiftOpts) {
            return dict as NSDictionary
        }
        return nil
    }

    /// Returns `{}` instead of failing. Mirrors `Qs.decodeOrEmpty`.
    @objc(decodeOrEmpty:)
    public static func decodeOrEmpty(_ input: Any?) -> NSDictionary {
        decodeOrEmpty(input, options: nil)
    }

    /// Returns `{}` instead of failing. Mirrors `Qs.decodeOrEmpty`.
    @objc(decodeOrEmpty:options:)
    public static func decodeOrEmpty(_ input: Any?, options: DecodeOptionsObjC?) -> NSDictionary {
        let bridged = bridgeInputForDecode(input)
        let swiftOpts = options?.swift ?? .init()
        let dict = Qs.decodeOrEmpty(bridged, options: swiftOpts)
        return dict as NSDictionary
    }

    /// Returns the provided default on failure. Mirrors `Qs.decodeOr`.
    @objc(decodeOr:default:)
    public static func decodeOr(_ input: Any?, `default` defaultValue: NSDictionary) -> NSDictionary
    {
        decodeOr(input, options: nil, default: defaultValue)
    }

    /// Returns the provided default on failure. Mirrors `Qs.decodeOr`.
    @objc(decodeOr:options:default:)
    public static func decodeOr(
        _ input: Any?,
        options: DecodeOptionsObjC?,
        `default` defaultValue: NSDictionary
    ) -> NSDictionary {
        let bridged = bridgeInputForDecode(input)
        let swiftOpts = options?.swift ?? .init()
        let swiftDefault = (defaultValue as? [String: Any]) ?? [:]
        let dict = Qs.decodeOr(bridged, options: swiftOpts, default: swiftDefault)
        return dict as NSDictionary
    }

    // MARK: - Async (callback-style), with Sendable-safe captures

    @objc(decodeAsyncOnMain:options:completion:)
    public static func decodeAsyncOnMain(
        _ input: Any?,
        options: DecodeOptionsObjC?,
        completion: @escaping @Sendable (NSDictionary?, NSError?) -> Void
    ) {
        let inBox = _UnsafeSendable(bridgeInputForDecode(input) as Any?)
        let optBox = _UnsafeSendable(options?.swift ?? .init())

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dict = try Qs.decode(inBox.value, options: optBox.value)
                DispatchQueue.main.async { completion(dict as NSDictionary, nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, error as NSError) }
            }
        }
    }

    @objc(decodeAsync:options:completion:)
    public static func decodeAsync(
        _ input: Any?,
        options: DecodeOptionsObjC?,
        completion: @escaping @Sendable (NSDictionary?, NSError?) -> Void
    ) {
        let inBox = _UnsafeSendable(bridgeInputForDecode(input) as Any?)
        let optBox = _UnsafeSendable(options?.swift ?? .init())

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dict = try Qs.decode(inBox.value, options: optBox.value)
                completion(dict as NSDictionary, nil)
            } catch {
                completion(nil, error as NSError)
            }
        }
    }
}

// Single generic box to silence Sendable warnings when crossing threads.
private final class _UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

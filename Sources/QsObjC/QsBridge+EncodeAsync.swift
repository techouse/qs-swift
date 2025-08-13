import Foundation

@objc extension QsBridge {
    @objc(encodeAsyncOnMain:options:completion:)
    public static func encodeAsyncOnMain(
        _ object: Any,
        options: EncodeOptionsObjC?,
        completion: @escaping @Sendable (NSString?, NSError?) -> Void
    ) {
        // Box captures to satisfy @Sendable
        let objBox = _AnySendableBox(object)
        let optBox = _AnySendableBox(options)

        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSError?
            let s = self.encode(objBox.value, options: optBox.value, error: &err)
            DispatchQueue.main.async { completion(s, err) }
        }
    }

    @objc(encodeAsync:options:completion:)
    public static func encodeAsync(
        _ object: Any,
        options: EncodeOptionsObjC?,
        completion: @escaping @Sendable (NSString?, NSError?) -> Void
    ) {
        let objBox = _AnySendableBox(object)
        let optBox = _AnySendableBox(options)

        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSError?
            let s = self.encode(objBox.value, options: optBox.value, error: &err)
            completion(s, err)
        }
    }
}

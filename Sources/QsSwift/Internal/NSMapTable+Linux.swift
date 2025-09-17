#if !canImport(Darwin)
    import Foundation
    #if canImport(ReerKit)
        import ReerKit

        /// Linux shim: adapt ReerKit's `WeakMap` (weak key + weak value) to the minimal
        /// `NSMapTable` API surface that Qs uses (weakToWeakObjects, setObject, object(forKey:)).
        ///
        /// This lets existing call sites keep using `NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()`
        /// without conditional code. On Apple platforms the real `NSMapTable` is used; on Linux this shim
        /// is compiled instead.
        final class NSMapTable<Key: AnyObject, Value: AnyObject> {
            // ReerKit exposes WeakMap which can be configured for weak keys and weak values.
            // We use NSObject as the storage types to interoperate with Foundation containers
            // commonly used as keys/values during encoding.
            private var map = WeakMap<WeakKeyValue, NSObject, NSObject>()

            /// Matches Foundation's convenience: create a weak-to-weak map table.
            static func weakToWeakObjects() -> NSMapTable<Key, Value> { NSMapTable<Key, Value>() }

            /// Store or remove a value for a key. Passing `nil` removes the entry.
            @inline(__always)
            func setObject(_ obj: Value?, forKey key: Key) {
                guard let keyNS = key as? NSObject else { return }
                if let vNS = obj as? NSObject {
                    map[keyNS] = vNS
                } else {
                    _ = map.removeValue(forKey: keyNS)
                }
            }

            /// Retrieve a value for a key, or `nil` if none (or if the key/value was released).
            @inline(__always)
            func object(forKey key: Key) -> Value? {
                guard let keyNS = key as? NSObject else { return nil }
                return map[keyNS] as? Value
            }
        }
    #else
        #error("ReerKit is required on Linux: add the ReerKit package or provide a compatible implementation")
    #endif
#endif

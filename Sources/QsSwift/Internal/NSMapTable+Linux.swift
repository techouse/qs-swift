#if os(Linux)
    import Foundation
    #if canImport(ReerKit)
        import ReerKit

        /// Linux shim: adapt ReerKit's `WeakMap` (weak key + weak value) to the minimal
        /// `NSMapTable` API surface that Qs uses (weakToWeakObjects, strongToStrongObjects,
        /// setObject, object(forKey:)).
        ///
        /// This lets existing call sites keep using `NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()`
        /// without conditional code. On Apple platforms the real `NSMapTable` is used; on Linux this shim
        /// is compiled instead.
        final class NSMapTable<Key: AnyObject, Value: AnyObject> {
            private enum StorageMode {
                case weak
                case strong
            }

            private let storageMode: StorageMode

            // Weak storage mode uses ReerKit's WeakMap.
            // We use NSObject as the storage types to interoperate with Foundation containers
            // commonly used as keys/values during encoding.
            private var weakMap = WeakMap<WeakKeyValue, NSObject, NSObject>()

            // Strong storage mode keeps object-identity keys and strongly-held values.
            private final class StrongEntry {
                let key: Key
                var value: Value

                init(key: Key, value: Value) {
                    self.key = key
                    self.value = value
                }
            }
            private var strongMap: [ObjectIdentifier: StrongEntry] = [:]

            private init(storageMode: StorageMode) {
                self.storageMode = storageMode
            }

            /// Matches Foundation's convenience: create a weak-to-weak map table.
            static func weakToWeakObjects() -> NSMapTable<Key, Value> {
                NSMapTable<Key, Value>(storageMode: .weak)
            }

            /// Matches Foundation's convenience: create a strong-to-strong map table.
            static func strongToStrongObjects() -> NSMapTable<Key, Value> {
                NSMapTable<Key, Value>(storageMode: .strong)
            }

            /// Store or remove a value for a key. Passing `nil` removes the entry.
            @inline(__always)
            func setObject(_ obj: Value?, forKey key: Key) {
                switch storageMode {
                case .strong:
                    let objectID = ObjectIdentifier(key)
                    if let obj {
                        strongMap[objectID] = StrongEntry(key: key, value: obj)
                    } else {
                        strongMap.removeValue(forKey: objectID)
                    }
                case .weak:
                    // ReerKit WeakMap storage here is NSObject-backed; non-NSObject keys are
                    // intentionally ignored to preserve prior shim behavior.
                    guard let keyNS = key as? NSObject else { return }
                    if let vNS = obj as? NSObject {
                        weakMap[keyNS] = vNS
                    } else {
                        _ = weakMap.removeValue(forKey: keyNS)
                    }
                }
            }

            /// Retrieve a value for a key, or `nil` if none (or if the key/value was released).
            @inline(__always)
            func object(forKey key: Key) -> Value? {
                switch storageMode {
                case .strong:
                    return strongMap[ObjectIdentifier(key)]?.value
                case .weak:
                    // Weak mode lookup mirrors setObject: keys not bridgeable to NSObject
                    // are treated as absent rather than trapping.
                    guard let keyNS = key as? NSObject else { return nil }
                    return weakMap[keyNS] as? Value
                }
            }
        }
    #else
        #error("ReerKit is required on Linux. Add it as a conditional dependency for Linux in Package.swift.")
    #endif
#endif

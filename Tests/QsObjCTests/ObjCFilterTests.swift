#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    @testable import QsObjC
    #if canImport(Testing)
        import Testing
    #endif

    @Suite("objc-filter")
    struct ObjCFilterTests {

        private func parts(_ s: NSString?) -> Set<String> {
            let str = s as String? ?? ""
            return Set(str.split(separator: "&").map(String.init))
        }

        @Test("FunctionFilter: drop underscore-prefixed keys")
        func function_dropUnderscoreKeys() {
            let opts = EncodeOptionsObjC()
            // return the sentinel to OMIT keys
            opts.filter = FilterObjC.function(
                FunctionFilterObjC { key, value in
                    key.hasPrefix("_") ? UndefinedObjC() : value
                })

            let input: NSDictionary = ["_a": 1, "b": 2]
            let out = QsBridge.encode(input, options: opts, error: nil)
            #expect(parts(out) == Set(["b=2"]))
        }

        @Test("IterableFilter: indices allowlist")
        func iterable_indices() {
            let opts = EncodeOptionsObjC()
            opts.encode = false
            // Include the root key "a" AND the indices
            opts.filter = FilterObjC.mixed(["a", 0, 2])

            let input: NSDictionary = ["a": ["b", "c", "d"]]
            let out = QsBridge.encode(input, options: opts, error: nil)
            #expect(parts(out) == Set(["a[0]=b", "a[2]=d"]))
        }

        @Test("Filter.including / excluding helpers")
        func including_excluding_helpers() {
            // Exclude "secret"
            let opts1 = EncodeOptionsObjC()
            opts1.filter = FilterObjC.excluding { $0 == "secret" }
            let s1 = QsBridge.encode(["user": "bob", "secret": "xyz"], options: opts1, error: nil)
            #expect(parts(s1) == Set(["user=bob"]))

            // Include only "user"
            let opts2 = EncodeOptionsObjC()
            opts2.filter = FilterObjC.including { $0 == "user" }
            let s2 = QsBridge.encode(["user": "bob", "city": "Paris"], options: opts2, error: nil)
            #expect(parts(s2) == Set(["user=bob"]))
        }
    }
#endif

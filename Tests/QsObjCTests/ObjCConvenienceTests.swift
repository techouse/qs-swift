#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    @testable import QsObjC
    import Foundation

    #if canImport(Testing)
        import Testing
    #else
        #error("The swift-testing package is required to build tests on Swift 5.x")
    #endif

    @Suite("convenience-objc")
    struct ConvenienceObjCTests {

        // MARK: encodeOrNil / encodeOrEmpty

        @Test("encodeOrNil (ObjC) → non-nil on success")
        func encodeOrNil_success() {
            let s = QsBridge.encodeOrNil(["a": "b"]) as String?
            #expect(s == "a=b")
        }

        @Test("encodeOrNil (ObjC) → nil on cyclic graph")
        func encodeOrNil_cycle() {
            let inner = NSMutableDictionary()
            inner["self"] = inner
            let input: [String: Any] = ["a": inner]  // supported top-level type
            let s = QsBridge.encodeOrNil(input) as String?
            #expect(s == nil)
        }

        @Test("encodeOrEmpty (ObjC) → empty on failure")
        func encodeOrEmpty_failure() {
            let inner = NSMutableDictionary()
            inner["self"] = inner
            let input: [String: Any] = ["a": inner]
            let s = QsBridge.encodeOrEmpty(input) as String
            #expect(s.isEmpty)
        }

        // MARK: decodeOrNil / decodeOrEmpty / decodeOr

        @Test("decodeOrNil (ObjC) → non-nil on success")
        func decodeOrNil_success() {
            let r = QsBridge.decodeOrNil("a=b") as? [String: Any]
            #expect(r?["a"] as? String == "b")
        }

        @Test("decodeOrNil (ObjC) → nil on error")
        func decodeOrNil_error() {
            let r = QsBridge.decodeOrNil(NSNumber(value: 1))
            #expect(r == nil)
        }

        @Test("decodeOrEmpty (ObjC) → empty on error")
        func decodeOrEmpty_error() {
            let r = QsBridge.decodeOrEmpty(NSNumber(value: 1)) as! [String: Any]
            #expect(r.isEmpty)
        }

        @Test("decodeOr (ObjC) default used only on error (not on nil input)")
        func decodeOr_default_semantics() {
            // Error → uses default
            let d1 = QsBridge.decodeOr(NSNumber(value: 1), default: ["x": "y"])
            #expect((d1 as! [String: Any])["x"] as? String == "y")

            // Nil input → empty (no error), does NOT use default (parity with Swift impl)
            let d2 = QsBridge.decodeOr(nil, default: ["x": "y"])
            #expect((d2 as! [String: Any]).isEmpty)
        }

        // MARK: async (ObjC callbacks)

        @Test("decodeAsyncOnMain (ObjC) calls back on main and returns value")
        func decodeAsyncOnMain_basic() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                QsBridge.decodeAsyncOnMain("a=b", options: nil) { dict, err in
                    #expect(Thread.isMainThread)
                    let r = dict as? [String: Any]
                    #expect(err == nil)
                    #expect(r?["a"] as? String == "b")
                    cont.resume()
                }
            }
        }

        @Test("decodeAsync (ObjC) calls back off-main with value")
        func decodeAsync_basic() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                QsBridge.decodeAsync("a=b", options: nil) { dict, err in
                    // No main-thread guarantee here
                    let r = dict as? [String: Any]
                    #expect(err == nil)
                    #expect(r?["a"] as? String == "b")
                    cont.resume()
                }
            }
        }
    }
#endif

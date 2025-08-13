#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import Testing

    @testable import QsObjC

    @Suite("ObjC bridge")
    struct ObjCBridgeTests {

        @Test("encode → decode round-trip (flat)")
        func roundtripFlat() throws {
            let input: NSDictionary = [
                "a": "1",
                "b": "two",
            ]

            // encode is non-throwing and returns NSString?
            let qs = QsObjC.encode(input)
            #expect(qs != nil)
            guard let qs else { return }  // stop if encode failed

            // decode takes non-optional NSString and throws
            var err: NSError?
            guard let output = QsObjC.decode(qs, error: &err) else {
                #expect(err == nil)  // will fail and surface the NSError
                return
            }

            #expect(((output["a"] as? String) ?? "") == "1")
            #expect(((output["b"] as? String) ?? "") == "two")
        }

        @Test("encode → decode round-trip (nested & list)")
        func roundtripNested() throws {
            let input: NSDictionary = [
                "user": [
                    "name": "alice",
                    "meta": ["id": "42"],
                ],
                "list": ["1", "2", "3"],
            ]

            let qs = QsObjC.encode(input)
            #expect(qs != nil)
            guard let qs else { return }

            var err: NSError?
            guard let output = QsObjC.decode(qs, error: &err) else {
                #expect(err == nil)  // will fail and surface the NSError
                return
            }

            let user = output["user"] as? NSDictionary
            #expect(((user?["name"] as? String) ?? "") == "alice")

            let meta = user?["meta"] as? NSDictionary
            #expect(((meta?["id"] as? String) ?? "") == "42")

            let list = output["list"] as? [Any]
            #expect((list?.count ?? 0) == 3)
            #expect(((list?[0] as? String) ?? "") == "1")
            #expect(((list?[1] as? String) ?? "") == "2")
            #expect(((list?[2] as? String) ?? "") == "3")
        }
    }
#endif

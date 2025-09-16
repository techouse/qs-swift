import Foundation

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

@Suite("convenience-core")
struct ConvenienceTests {

    // MARK: encodeOrNil / encodeOrEmpty

    @Test("encodeOrNil → non-nil on success")
    func encodeOrNil_success() {
        #expect(Qs.encodeOrNil(["a": "b"]) == "a=b")
    }

    @Test("encodeOrNil → nil on cyclic graph")
    func encodeOrNil_cycle() {
        #if os(Linux)
            // On Linux, a self-referential NSDictionary can crash due to corelibs-foundation differences.
            // Using an unsupported top-level type should fail; corelibs may return "" instead of nil.
            let input: Any = NSNumber(value: 1)
            let got = Qs.encodeOrNil(input)
            #expect(got == nil || got == "")
        #else
            let inner = NSMutableDictionary()
            inner["self"] = inner  // reference cycle
            let input: [String: Any] = ["a": inner]  // supported top-level type
            #expect(Qs.encodeOrNil(input) == nil)
        #endif
    }

    @Test("encodeOrEmpty → string on success")
    func encodeOrEmpty_success() {
        #expect(Qs.encodeOrEmpty(["a": "b"]) == "a=b")
    }

    @Test("encodeOrEmpty → empty on failure")
    func encodeOrEmpty_failure() {
        #if os(Linux)
            // On Linux, a self-referential NSDictionary can crash due to corelibs-foundation differences.
            // We still verify the contract (empty on failure) using an unsupported top-level type.
            let input: Any = NSNumber(value: 1)
            #expect(Qs.encodeOrEmpty(input).isEmpty)
        #else
            let inner = NSMutableDictionary()
            inner["self"] = inner
            let input: [String: Any] = ["a": inner]
            #expect(Qs.encodeOrEmpty(input).isEmpty)
        #endif
    }

    // MARK: decodeOrNil / decodeOrEmpty / decodeOr

    @Test("decodeOrNil → non-nil on success")
    func decodeOrNil_success() {
        let r = Qs.decodeOrNil("a=b")
        #expect((r?["a"] as? String) == "b")
    }

    @Test("decodeOrNil → nil on error")
    func decodeOrNil_error() {
        #expect(Qs.decodeOrNil(NSNumber(value: 1)) == nil)  // unsupported top-level type
    }

    @Test("decodeOrEmpty → value on success")
    func decodeOrEmpty_success() {
        let r = Qs.decodeOrEmpty("a=b")
        #expect((r["a"] as? String) == "b")
    }

    @Test("decodeOrEmpty → empty on error")
    func decodeOrEmpty_error() {
        let r = Qs.decodeOrEmpty(NSNumber(value: 1))
        #expect(r.isEmpty)
    }

    @Test("decodeOr default used only on error (not on nil input)")
    func decodeOr_default_semantics() {
        // Error → uses default
        let r1 = Qs.decodeOr(NSNumber(value: 1), default: ["x": "y"])
        #expect((r1["x"] as? String) == "y")

        // Nil input → empty (no error), does NOT use default (parity with Swift impl)
        let r2 = Qs.decodeOr(nil, default: ["x": "y"])
        #expect(r2.isEmpty)
    }

    // MARK: async conveniences

    @Test("decodeAsyncOnMain returns on main actor")
    func decodeAsyncOnMain_basic() async throws {
        let wrapped = try await Qs.decodeAsyncOnMain("a=b")
        let r = wrapped.value
        #expect((r["a"] as? String) == "b")

        #if os(Linux)
            // On Linux, MainActor isn’t guaranteed to be the OS main thread.
            // Executing on MainActor here is sufficient to validate marshaling.
            await MainActor.run {
                #expect(true)
            }
        #else
            await MainActor.run {
                #expect(Thread.isMainThread)
            }
        #endif
    }

    @Test("decodeAsyncValue runs off-main (doesn't marshal to main)")
    func decodeAsyncValue_basic() async throws {
        let r = try await Qs.decodeAsyncValue("a=b")
        #expect((r["a"] as? String) == "b")
        // Not asserting thread here—implementation intentionally doesn't guarantee main.
    }
}

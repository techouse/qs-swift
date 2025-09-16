import Foundation

@testable import QsSwift

// for pthread_main_np()
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

@Suite("core-extras")
struct CoreExtrasTests {

    #if !os(Linux)
        @Test("EncodeError.cyclicObject is thrown for NSDictionary self-cycle")
        func encode_cycleNSDictionary() {
            let m = NSMutableDictionary()
            m["self"] = m
            #expect(throws: EncodeError.cyclicObject) {
                _ = try Qs.encode(m)
            }
        }
    #else
        @Test("NSDictionary self-cycle skipped on Linux (corelibs-foundation segfault)")
        func encode_cycleNSDictionary_linux_skip() {
            Issue.record(
                "Skipped on Linux: self-referential NSDictionary can segfault in swift-corelibs-foundation before the cycle guard triggers."
            )
        }
    #endif

    @Test("DecodeError as NSError: parameterLimitExceeded populates domain/code/userInfo")
    func decode_errorAsNSError_parameterLimitExceeded() {
        do {
            _ = try Qs.decode(
                "a=b&c=d", options: .init(parameterLimit: 1, throwOnLimitExceeded: true))
            Issue.record("expected throw")
        } catch {
            let ns = error as NSError
            #expect(ns.domain == DecodeError.errorDomain)
            #expect(ns.code == DecodeError.parameterLimitExceeded(limit: 1).errorCode)
            #expect((ns.userInfo[DecodeError.userInfoLimitKey] as? Int) == 1)
        }
    }

    @Test("EncodeOptions.copy respects double-optional semantics")
    func encodeOptions_copy_doubleOptional() {
        let base = EncodeOptions(encoder: nil, listFormat: nil, sort: nil)
        // set only listFormat, clear sort explicitly
        let next = base.copy(listFormat: .some(.brackets), sort: .some(nil))
        #expect(next.getListFormat == .brackets)
        #expect(next.sort == nil)
        // leave encoder as-is (nil) by passing default (no change)
        #expect(next.getEncoder("x") == Utils.encode("x", charset: .utf8, format: .rfc3986))
    }

    @Test("Sentinel helpers")
    func sentinel_helpers() {
        #expect(Sentinel.match(encodedPart: Sentinel.iso.encoded) == .iso)
        #expect(Sentinel.match(encodedPart: Sentinel.charset.encoded) == .charset)
        #expect(Sentinel.forCharset(.utf8) == .charset)
        #expect(Sentinel.forCharset(.isoLatin1) == .iso)
        #expect("\(Sentinel.iso)" == Sentinel.iso.encoded)  // description parity
    }

    @Test("custom Sorter orders keys deterministically")
    func encode_customSorter() throws {
        // sort keys numerically if possible, then lexicographically
        let sorter: Sorter = { a, b in
            let sa = String(describing: a ?? "")
            let sb = String(describing: b ?? "")
            if let ia = Int(sa), let ib = Int(sb) {
                return ia == ib ? 0 : (ia < ib ? -1 : 1)
            }
            return sa.compare(sb).rawValue
        }
        let s = try Qs.encode(
            ["10": "z", "2": "y", "a": "b"],
            options: .init(encode: false, sort: sorter))
        #expect(s == "2=y&10=z&a=b")
    }
}

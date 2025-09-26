import Foundation

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

@Suite("model-coverage")
struct ModelCoverageTests {

    @Test("FunctionFilter factories produce expected behavior and descriptions")
    func functionFilter_factories() {
        let excluding = FunctionFilter.excluding { $0.hasPrefix("_") }
        #expect(excluding.description.contains("FunctionFilter"))
        #expect(excluding.function("keep", "value") as? String == "value")
        #expect(excluding.function("_secret", "value") == nil)

        let including = FunctionFilter.including { $0 == "keep" }
        #expect(including.function("keep", 42) as? Int == 42)
        #expect(including.function("drop", 42) == nil)

        let transforming = FunctionFilter.transforming([
            "name": { value in (value as? String)?.uppercased() ?? value },
            "count": { value in (value as? Int).map { $0 * 2 } },
        ])
        #expect(transforming.function("name", "alex") as? String == "ALEX")
        #expect((transforming.function("count", 3) as? Int?).flatMap { $0 } == 6)
        #expect(transforming.function("other", "stay") as? String == "stay")
    }

    @Test("IterableFilter factories capture provided keys and indices")
    func iterableFilter_factories() {
        let keysFilter = IterableFilter.keys("a", "b")
        #expect((keysFilter.iterable as? [String]) == ["a", "b"])
        #expect(keysFilter.description.contains("IterableFilter"))

        let indicesFilter = IterableFilter.indices(0, 2)
        #expect((indicesFilter.iterable as? [Int]) == [0, 2])

        let mixedFilter = IterableFilter.mixed("name", 4)
        #expect(mixedFilter.iterable.count == 2)
        #expect(mixedFilter.iterable[0] as? String == "name")
        #expect(mixedFilter.iterable[1] as? Int == 4)
    }

    @Test("Duplicates exposes readable descriptions")
    func duplicates_descriptions() {
        #expect(Duplicates.combine.description == "combine")
        #expect(Duplicates.first.description == "first")
        #expect(Duplicates.last.description == "last")
    }

    @Test("DecodeError bridged metadata matches expectations")
    func decodeError_bridging() {
        let notPositive = DecodeError.parameterLimitNotPositive
        let exceeding = DecodeError.parameterLimitExceeded(limit: 2)
        let listLimit = DecodeError.listLimitExceeded(limit: 1)
        let depthExceeded = DecodeError.depthExceeded(maxDepth: 3)

        #expect(notPositive.description.contains("Parameter limit"))
        #expect(exceeding.description.contains("Only 2 parameter"))
        #expect(listLimit.description.contains("List limit"))
        #expect(depthExceeded.description.contains("strictDepth"))

        let nsError = exceeding as NSError
        #expect(nsError.domain == DecodeError.errorDomain)
        #expect(nsError.code == exceeding.errorCode)
        #expect((nsError.userInfo[DecodeError.userInfoLimitKey] as? Int) == 2)

        let depthNSError = depthExceeded as NSError
        #expect(depthNSError.code == depthExceeded.errorCode)
        #expect((depthNSError.userInfo[DecodeError.userInfoMaxDepthKey] as? Int) == 3)
    }

    @Test("Unsafe sendable wrapper exposes stored value")
    func unsafeSendable_wrapsValue() {
        let boxed = _UnsafeSendable(["k": "v"])
        #expect(boxed.value["k"] == "v")

        let alt = _UnsafeSendable(wrapping: 42)
        #expect(alt.value == 42)
    }

    #if canImport(Darwin)
        @Test("WeakWrapper equality, hashing, and lifecycle semantics")
        func weakWrapper_semantics() {
            final class Box {}

            var pair: (WeakWrapper, WeakWrapper)?

            autoreleasepool {
                let object = Box()
                let wrapperA = WeakWrapper(object)
                let wrapperB = WeakWrapper(object)

                #expect(wrapperA.isEqual(wrapperA))
                #expect(wrapperA.isEqual(wrapperB))
                #expect(wrapperA.hash == wrapperB.hash)
                #expect(wrapperA.referent != nil)

                pair = (wrapperA, wrapperB)
            }

            guard let stored = pair else {
                Issue.record("Expected wrappers to persist")
                return
            }

            let (wrapperA, wrapperB) = stored

            #expect(wrapperA.referent == nil)
            #expect(wrapperB.referent == nil)
            #expect(wrapperA.isEqual(wrapperB) == false)
            #expect(wrapperA.description.contains("<deallocated>"))
            #expect(wrapperA.debugDescription == wrapperA.description)
        }
    #endif

    @Test("Undefined convenience helpers round-trip the singleton")
    func undefined_singletonHelpers() {
        #expect(Undefined.instance == Undefined())
        #expect(Undefined.callAsFunction() == Undefined.instance)
        #expect(Undefined().description == "Undefined")
    }
}

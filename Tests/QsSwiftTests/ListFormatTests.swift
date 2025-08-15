@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct ListFormatTests {
    @Test("ListFormat.description returns readable labels")
    func listFormat_description_labels() {
        #expect(String(describing: ListFormat.brackets) == "brackets")
        #expect(ListFormat.comma.description == "comma")
        #expect("\(ListFormat.repeatKey)" == "repeat")
        #expect("\(ListFormat.indices)" == "indices")
    }
}

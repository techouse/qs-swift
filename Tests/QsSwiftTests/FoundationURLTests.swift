import Foundation

@testable import QsSwift

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct FoundationURLTests {
    @Test("URLComponents helpers leave nil and empty encoded output unchanged")
    func urlComponents_nilAndEmptyOutputAreNoOps() throws {
        var nilComponents = URLComponents(string: "https://example.com/products?existing=x%20y#frag")!
        let nilBefore = nilComponents.string

        try nilComponents.appendQsQueryItems(nil)

        #expect(nilComponents.string == nilBefore)

        var emptyComponents = URLComponents(string: "https://example.com/products?existing=x%20y#frag")!
        let emptyBefore = emptyComponents.string

        try emptyComponents.appendQsQueryItems([String: Any]())

        #expect(emptyComponents.string == emptyBefore)
    }

    @Test("URLComponents helper appends simple, nested, and array values without double encoding")
    func urlComponents_appendsNestedQueryWithoutDoubleEncoding() throws {
        var simple = URLComponents(string: "https://api.example.com/products")!

        try simple.appendQsQueryItems(["a": "b"])

        #expect(simple.url?.absoluteString == "https://api.example.com/products?a=b")

        var components = URLComponents(string: "https://api.example.com/products")!
        let input: [String: Any] = [
            "filter": [
                "where": [
                    "age": ["gte": 30],
                    "name": "John",
                ]
            ],
            "tags": ["a", "b"],
        ]

        try components.appendQsQueryItems(
            input,
            options: EncodeOptions(sort: Self.lexicalSort)
        )

        let url = try #require(components.url)
        #expect(
            url.absoluteString
                == "https://api.example.com/products?filter%5Bwhere%5D%5Bage%5D%5Bgte%5D=30"
                + "&filter%5Bwhere%5D%5Bname%5D=John&tags%5B0%5D=a&tags%5B1%5D=b"
        )
        #expect(url.absoluteString.contains("filter%5Bwhere%5D"))
        #expect(!url.absoluteString.contains("%255B"))
    }

    @Test("URLComponents helper preserves structured list values")
    func urlComponents_appendsListOfDictionaries() throws {
        var components = URLComponents(string: "https://api.example.com/products")!

        try components.appendQsQueryItems(
            ["items": [["id": 1], ["id": 2]]],
            options: EncodeOptions(sort: Self.lexicalSort)
        )

        #expect(
            components.percentEncodedQuery
                == "items%5B0%5D%5Bid%5D=1&items%5B1%5D%5Bid%5D=2"
        )
    }

    @Test("URLComponents helper preserves duplicate keys, empty values, and name-only values")
    func urlComponents_preservesDuplicateEmptyAndNameOnlyValues() throws {
        var duplicates = URLComponents(string: "https://example.com/products")!

        try duplicates.appendQsQueryItems(
            ["tag": ["a", "b"]],
            options: EncodeOptions(listFormat: .repeatKey)
        )

        #expect(duplicates.percentEncodedQuery == "tag=a&tag=b")

        var emptyAndBare = URLComponents(string: "https://example.com/products")!

        try emptyAndBare.appendQsQueryItems(
            ["bare": NSNull(), "empty": ""],
            options: EncodeOptions(strictNullHandling: true, sort: Self.lexicalSort)
        )

        #expect(emptyAndBare.percentEncodedQuery == "bare&empty=")
        #expect(emptyAndBare.url?.absoluteString == "https://example.com/products?bare&empty=")
    }

    @Test("URLComponents helper preserves existing query text, fragments, and URL components")
    func urlComponents_preservesExistingQueryAndURLParts() throws {
        var components = URLComponents()
        components.scheme = "https"
        components.user = "user"
        components.password = "pass"
        components.host = "api.example.com"
        components.port = 8443
        components.path = "/products"
        components.percentEncodedQuery = "existing=x%20y&flag"
        components.fragment = "frag"

        try components.appendQsQueryItems(
            ["filter": ["name": "John"]],
            options: EncodeOptions(sort: Self.lexicalSort)
        )

        #expect(
            components.url?.absoluteString
                == "https://user:pass@api.example.com:8443/products"
                + "?existing=x%20y&flag&filter%5Bname%5D=John#frag"
        )
    }

    @Test("URL helper returns a new URL and preserves the original")
    func url_appendingReturnsNewURL() throws {
        let original = URL(string: "https://example.com/products?existing=x#frag")!

        let next = try original.appendingQsQueryItems(["a": ["b": "c"]])

        #expect(original.absoluteString == "https://example.com/products?existing=x#frag")
        #expect(next.absoluteString == "https://example.com/products?existing=x&a%5Bb%5D=c#frag")
    }

    @Test("URL helper supports relative URLs")
    func url_appendingSupportsRelativeURLs() throws {
        let original = URL(string: "/products?existing=x#frag")!

        let next = try original.appendingQsQueryItems(["a": "b"])

        #expect(next.relativeString == "/products?existing=x&a=b#frag")
    }

    @Test("URL helpers ignore addQueryPrefix and preserve custom delimiters")
    func urlHelpers_ignoreQueryPrefixAndPreserveDelimiter() throws {
        var prefixed = URLComponents(string: "https://example.com/products")!

        try prefixed.appendQsQueryItems(
            ["a": "b"],
            options: EncodeOptions(addQueryPrefix: true)
        )

        #expect(prefixed.percentEncodedQuery == "a=b")

        var semicolon = URLComponents(string: "https://example.com/products?existing=x")!

        try semicolon.appendQsQueryItems(
            ["a": "b", "c": "d"],
            options: EncodeOptions(delimiter: ";", sort: Self.lexicalSort)
        )

        #expect(semicolon.percentEncodedQuery == "existing=x;a=b;c=d")
        #expect(semicolon.url?.absoluteString == "https://example.com/products?existing=x;a=b;c=d")
    }

    @Test("URL helpers normalize raw and values-only encoding options")
    func urlHelpers_normalizeRawEncodingOptions() throws {
        var rawKeys = URLComponents(string: "https://example.com/products")!

        try rawKeys.appendQsQueryItems(
            ["a": ["b": "c"]],
            options: EncodeOptions(encode: false)
        )

        #expect(rawKeys.percentEncodedQuery == "a%5Bb%5D=c")

        var valuesOnly = URLComponents(string: "https://example.com/products")!

        try valuesOnly.appendQsQueryItems(
            ["a": ["b": "c d"]],
            options: EncodeOptions(encodeValuesOnly: true)
        )

        #expect(valuesOnly.percentEncodedQuery == "a%5Bb%5D=c%20d")
    }

    @Test("URL helpers report invalid custom encoder output without mutating components")
    func urlHelpers_invalidCustomEncoderOutput() throws {
        let invalidEncoder: ValueEncoder = { value, _, _ in
            String(describing: value ?? "")
        }
        let options = EncodeOptions(encoder: invalidEncoder)
        var components = URLComponents(string: "https://example.com/products?existing=x")!

        #expect(throws: QsURLQueryError.invalidPercentEncodedQuery) {
            try components.appendQsQueryItems(["a": ["b": "c"]], options: options)
        }
        #expect(components.percentEncodedQuery == "existing=x")

        let didAppend = components.appendQsQueryItemsIfPossible(["a": ["b": "c"]], options: options)
        #expect(!didAppend)
        #expect(components.percentEncodedQuery == "existing=x")

        let url = URL(string: "https://example.com/products")!
        #expect(url.appendingQsQueryItemsOrNil(["a": ["b": "c"]], options: options) == nil)

        let unicodeEncoder: ValueEncoder = { _, _, _ in
            "é"
        }
        var unicodeComponents = URLComponents(string: "https://example.com/products?existing=x")!

        #expect(throws: QsURLQueryError.invalidPercentEncodedQuery) {
            try unicodeComponents.appendQsQueryItems(["a": "b"], options: EncodeOptions(encoder: unicodeEncoder))
        }
        #expect(unicodeComponents.percentEncodedQuery == "existing=x")
    }

    private static func lexicalSort(_ lhs: Any?, _ rhs: Any?) -> Int {
        let left = String(describing: lhs ?? "")
        let right = String(describing: rhs ?? "")
        return left.compare(right).rawValue
    }
}

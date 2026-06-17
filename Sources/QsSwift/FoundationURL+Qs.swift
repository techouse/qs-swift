import Foundation

/// Errors thrown while appending QsSwift output to Foundation URL types.
public enum QsURLQueryError: Error, Equatable, Sendable {
    /// The generated query was not valid for `URLComponents.percentEncodedQuery`.
    case invalidPercentEncodedQuery

    /// Foundation could not construct a `URL` from the updated URL components.
    case invalidURL
}

public extension URLComponents {
    /// Appends QsSwift-encoded query items to this component's percent-encoded query.
    ///
    /// This method appends to `percentEncodedQuery` instead of `queryItems` so qs-style bracket keys stay encoded as
    /// `%5B` / `%5D` instead of being encoded again as `%255B` / `%255D`.
    ///
    /// - Parameters:
    ///   - value: The value to encode and append. Passing `nil` leaves the receiver unchanged.
    ///   - options: Encoder settings. URL helpers force URL-safe encoding internally while preserving structural
    ///     options such as delimiter, list format, sorting, null handling, and custom encoders.
    /// - Throws: `EncodeError` from `Qs.encode`, or `QsURLQueryError.invalidPercentEncodedQuery` when the generated
    ///   query is not valid percent-encoded query text.
    mutating func appendQsQueryItems(
        _ value: Any?,
        options: EncodeOptions = .init()
    ) throws {
        guard let encoded = try Qs._encodedURLQuery(value, options: options) else {
            return
        }

        let existingQuery = percentEncodedQuery ?? ""
        let nextQuery =
            existingQuery.isEmpty
            ? encoded.query
            : existingQuery + encoded.delimiter + encoded.query

        guard Qs._isValidPercentEncodedQuery(nextQuery) else {
            throw QsURLQueryError.invalidPercentEncodedQuery
        }

        percentEncodedQuery = nextQuery
    }

    /// Attempts to append QsSwift-encoded query items, returning `false` on failure.
    ///
    /// The receiver is restored to its original percent-encoded query if encoding or validation fails.
    @discardableResult
    mutating func appendQsQueryItemsIfPossible(
        _ value: Any?,
        options: EncodeOptions = .init()
    ) -> Bool {
        let originalQuery = percentEncodedQuery

        do {
            try appendQsQueryItems(value, options: options)
            return true
        } catch {
            percentEncodedQuery = originalQuery
            return false
        }
    }
}

public extension URL {
    /// Returns a new URL with QsSwift-encoded query items appended.
    ///
    /// The original URL is not mutated. Existing query text and fragments are preserved.
    ///
    /// - Parameters:
    ///   - value: The value to encode and append. Passing `nil` returns an equivalent URL.
    ///   - options: Encoder settings.
    /// - Throws: `EncodeError` from `Qs.encode`, `QsURLQueryError.invalidPercentEncodedQuery`, or
    ///   `QsURLQueryError.invalidURL` if Foundation cannot rebuild the URL.
    func appendingQsQueryItems(
        _ value: Any?,
        options: EncodeOptions = .init()
    ) throws -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            throw QsURLQueryError.invalidURL
        }

        try components.appendQsQueryItems(value, options: options)

        guard let url = components.url else {
            throw QsURLQueryError.invalidURL
        }

        return url
    }

    /// Returns a new URL with QsSwift-encoded query items appended, or `nil` on failure.
    func appendingQsQueryItemsOrNil(
        _ value: Any?,
        options: EncodeOptions = .init()
    ) -> URL? {
        try? appendingQsQueryItems(value, options: options)
    }
}

extension Qs {
    @usableFromInline
    internal static func _encodedURLQuery(
        _ value: Any?,
        options: EncodeOptions
    ) throws -> (query: String, delimiter: String)? {
        guard value != nil else {
            return nil
        }

        let urlOptions = options.copy(
            addQueryPrefix: false,
            encode: true,
            encodeValuesOnly: false
        )
        let query = try encode(value, options: urlOptions)

        guard !query.isEmpty else {
            return nil
        }

        guard _isValidPercentEncodedQuery(query) else {
            throw QsURLQueryError.invalidPercentEncodedQuery
        }

        return (query, urlOptions.delimiter)
    }

    @usableFromInline
    internal static func _isValidPercentEncodedQuery(_ query: String) -> Bool {
        let scalars = query.unicodeScalars
        var index = scalars.startIndex

        while index != scalars.endIndex {
            let scalar = scalars[index]

            if scalar.value == 37 {
                let firstHexIndex = scalars.index(after: index)
                guard firstHexIndex != scalars.endIndex else {
                    return false
                }

                let secondHexIndex = scalars.index(after: firstHexIndex)
                guard secondHexIndex != scalars.endIndex else {
                    return false
                }

                guard isHexDigit(scalars[firstHexIndex]), isHexDigit(scalars[secondHexIndex]) else {
                    return false
                }

                index = scalars.index(after: secondHexIndex)
            } else {
                guard scalar.value <= 127, CharacterSet.urlQueryAllowed.contains(scalar) else {
                    return false
                }

                index = scalars.index(after: index)
            }
        }

        return true
    }

    @inlinable
    internal static func isHexDigit(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...70, 97...102:
            return true
        default:
            return false
        }
    }
}

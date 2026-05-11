---
name: qs-swift
description: Use this skill whenever a user wants to install, configure, troubleshoot, or write Swift, SwiftPM, Apple-platform, Linux Swift, or Objective-C application code for encoding and decoding nested query strings with the QsSwift package. This skill helps produce practical Qs.decode, Qs.encode, decodeAsync, QsObjC, DecodeOptions, and EncodeOptions snippets, explain option tradeoffs, and avoid QsSwift edge-case pitfalls around lists, dot notation, duplicates, nil and NSNull handling, charset sentinels, depth limits, Objective-C bridging, deterministic ordering, and untrusted input.
---

# QsSwift Usage Assistant

Help users parse and build query strings with the Swift `QsSwift` package and
the Objective-C `QsObjC` bridge. Focus on user application code and
interoperability outcomes, not repository maintenance.

## Start With Inputs

Before producing a final snippet, collect only the missing details that change
the code:

- Runtime: Swift app, SwiftPM package, iOS/macOS/tvOS/watchOS app, Linux Swift,
  Objective-C app, tests, backend code, or generated example.
- Direction: decode an incoming query string, encode Swift/Foundation data,
  decode asynchronously, use the Objective-C bridge, or normalize query-string
  handling around an existing URL/request object.
- The actual query string or data structure when available.
- Target API convention for lists: indexed brackets, empty brackets, repeated
  keys, or comma-separated values.
- Whether the query may include a leading `?`, dot notation, literal dots in
  keys, duplicate keys, custom delimiters, comma-separated lists, null-like
  values, ISO-8859-1/legacy charset behavior, deterministic ordering needs,
  Objective-C bridging, or untrusted user input.

Do not over-ask when the desired behavior is obvious. State assumptions in the
answer and give the user a concrete snippet they can paste.

## Installation

Use Swift Package Manager for normal Swift consumers:

```swift
dependencies: [
    .package(url: "https://github.com/techouse/qs-swift", from: "<version>")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "QsSwift", package: "qs-swift")
        ]
    )
]
```

In Xcode, add `https://github.com/techouse/qs-swift` with File > Add Package
Dependencies, then add `QsSwift` to the target.

Use the `QsObjC` product only when Objective-C callers need the bridge:

```swift
.product(name: "QsObjC", package: "qs-swift")
```

The main manifest uses Swift tools 6.0, and the repo also ships a Swift 5.10
compatibility manifest. Platform floors are macOS 12, iOS 13, tvOS 13, and
watchOS 8. Linux support is available for SwiftPM users; the Objective-C bridge
is Apple-platform only because it requires the Objective-C runtime.

## Public API

Prefer the `Qs` facade for Swift application code:

```swift
import QsSwift

let values: [String: Any] = try Qs.decode("a[b]=c")
let query: String = try Qs.encode(["a": ["b": "c"]])
```

Use convenience wrappers only when swallowing errors is intended:

```swift
let values = Qs.decodeOrEmpty("a[b]=c")
let query = Qs.encodeOrEmpty(["a": "c"])
let result = Qs.decodeResult("a[b]=c")
```

For large or deep queries in UI code, use async decode:

```swift
let decoded = try await Qs.decodeAsyncOnMain("?a[b]=c", options: .init(ignoreQueryPrefix: true))
let values = decoded.value
```

From Objective-C, import the bridge and use the `Qs` facade exposed by `QsObjC`:

```objc
@import QsObjC;

NSError *error = nil;
NSDictionary *values = [Qs decode:@"a[b]=c" options:nil error:&error];
NSString *query = [Qs encode:@{ @"a": @{ @"b": @"c" } } options:nil error:&error];
```

## Base Patterns

Decode a query string into nested Swift values:

```swift
import QsSwift

let values = try Qs.decode("filter[status]=open&tag[]=swift&tag[]=ios")

// values["filter"] is a nested dictionary; values["tag"] is a list.
```

Encode nested Swift values into a query string:

```swift
import QsSwift

let query = try Qs.encode([
    "filter": ["status": "open"],
    "tag": ["swift", "ios"],
])

// filter%5Bstatus%5D=open&tag%5B0%5D=swift&tag%5B1%5D=ios
```

For readable examples, tests, or APIs that expect unescaped bracket syntax, set
`encode: false` intentionally:

```swift
let query = try Qs.encode(
    ["a": ["b": "c"]],
    options: .init(encode: false)
)

// a[b]=c
```

## URL And App Integration

When decoding a URL, prefer the percent-encoded query component so qs-style
syntax is still visible to QsSwift:

```swift
let rawQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
let values = try Qs.decode(
    rawQuery
)
```

If the input may include the leading question mark, set `ignoreQueryPrefix:
true`.

When encoding into a URL, use `addQueryPrefix: true` only when the caller wants
the leading question mark:

```swift
let query = try Qs.encode(
    ["page": 2, "tag": ["api", "docs"]],
    options: .init(addQueryPrefix: true, listFormat: .repeatKey)
)

// ?page=2&tag=api&tag=docs
```

Use `OrderedDictionary` from `OrderedCollections` or pass an explicit `sort`
when deterministic output matters. Plain `Dictionary` traversal order is not a
good cross-run contract for assertions, signatures, or caches.

## Decode Recipes

Use these options with `Qs.decode(query, options: .init(...))`:

- Leading question mark: `ignoreQueryPrefix: true`.
- Dot notation such as `a.b=c`: `allowDots: true`.
- Double-encoded literal dots in keys such as `name%252Eobj.first=John`:
  `decodeDotInKeys: true`; this implies dot notation unless explicitly
  contradicted.
- Duplicate keys: `duplicates: .combine` keeps all values as a list; use
  `.first` or `.last` to collapse.
- Bracket lists: enabled by default; set `parseLists: false` to treat list
  syntax as dictionary keys.
- Empty list tokens such as `foo[]`: `allowEmptyLists: true`.
- Sparse numeric indices: `allowSparseLists: true` preserves holes as
  `NSNull()` placeholders; the default compacts lists.
- Large list indices: default `listLimit` is `20`; indices above the limit
  become dictionary keys.
- Comma-separated values such as `a=b,c`: `comma: true`.
- Tokens without `=` as `NSNull()`: `strictNullHandling: true`.
- Custom delimiters: `delimiter: StringDelimiter(";")` or
  `delimiter: try RegexDelimiter("[;,]")`.
- Legacy charset input: `charset: .isoLatin1`; use `charsetSentinel: true`
  when a form may include `utf8=...` to signal the real charset.
- HTML numeric entities: `interpretNumericEntities: true`, usually with
  ISO-8859-1 or charset sentinel handling.
- Custom scalar decoding: use `decoder` when key/value behavior differs; key
  decoding should return values that can be stringified.
- Untrusted input: keep `depth`, `parameterLimit`, and `listLimit` bounded; use
  `strictDepth: true` and `throwOnLimitExceeded: true` when callers need hard
  failures instead of soft limiting.

Example for a request query:

```swift
import QsSwift

let values = try Qs.decode(
    "?filter.status=open&tag=swift&tag=ios",
    options: .init(
        allowDots: true,
        duplicates: .combine,
        ignoreQueryPrefix: true
    )
)
```

## Encode Recipes

Use these options with `Qs.encode(data, options: .init(...))`:

- List style defaults to `.indices`:
  `tag%5B0%5D=swift&tag%5B1%5D=ios`.
- Empty brackets: `listFormat: .brackets`.
- Repeated keys: `listFormat: .repeatKey`.
- Comma-separated values: `listFormat: .comma`.
- Single-item comma lists that must round-trip as lists:
  `commaRoundTrip: true`.
- Drop `nil` and `NSNull` items before comma-joining lists:
  `commaCompactNulls: true`.
- Dot notation for nested dictionaries: `allowDots: true`, commonly with
  `encode: false` for readable unescaped dots.
- Literal dots in keys: `encodeDotInKeys: true`; `allowDots` is implied when it
  is not explicitly set.
- Add a leading `?`: `addQueryPrefix: true`.
- Custom pair delimiter: `delimiter: ";"`.
- Preserve readable bracket/dot keys while encoding values:
  `encodeValuesOnly: true`.
- Disable percent encoding entirely for debugging or documented examples:
  `encode: false`.
- Emit `NSNull()` without `=`: `strictNullHandling: true`.
- Omit `nil` and `NSNull()` values: `skipNulls: true`.
- Omit selected values: return `Undefined()` from a `FunctionFilter`, use an
  `IterableFilter`, or remove entries before calling `encode`.
- Emit empty lists as `foo[]`: `allowEmptyLists: true`.
- Legacy form spaces as `+`: `format: .rfc1738`; the default is `.rfc3986`,
  which emits spaces as `%20`.
- Legacy charset output: `charset: .isoLatin1`; use `charsetSentinel: true` to
  prepend the `utf8=...` sentinel.
- Custom behavior: use `encoder`, `dateSerializer`, `sort`, or `filter` when
  the target API needs special scalar encoding, date formatting, stable key
  order, or selected fields.

Example for an API that expects repeated keys:

```swift
import QsSwift

let query = try Qs.encode(
    [
        "q": "query strings",
        "tag": ["swift", "ios"],
    ],
    options: .init(
        addQueryPrefix: true,
        listFormat: .repeatKey
    )
)

// ?q=query%20strings&tag=swift&tag=ios
```

## Objective-C Bridge

Use `QsObjC` when Objective-C source needs to call the library. Match the Swift
options with `QsDecodeOptions`, `QsEncodeOptions`, `QsDuplicates*`,
`QsListFormat*`, and `QsFormat*` bridge types:

```objc
@import QsObjC;

QsEncodeOptions *options = [QsEncodeOptions new];
options.encode = NO;
options.listFormat = QsListFormatRepeatKey;

NSError *error = nil;
NSString *query = [Qs encode:@{ @"tag": @[ @"swift", @"ios" ] } options:options error:&error];

// tag=swift&tag=ios
```

Mention Objective-C caveats when relevant:

- `NSDictionary` order is not stable; use a sort comparator when output order
  matters.
- The bridge is Apple-platform only.
- Prefer bridge option objects over trying to import Swift-only option structs
  directly into Objective-C.

## Combinations To Check

Warn or adjust before giving code for these cases:

- `DecodeOptions(decodeDotInKeys: true, allowDots: false)` is invalid.
- `parameterLimit` must be positive and `depth` must be non-negative.
- `throwOnLimitExceeded: true` turns parameter and list limit violations into
  thrown errors; without it, parsing truncates or falls back.
- `strictDepth: true` throws on well-formed depth overflow; with the default
  `false`, the remainder beyond `depth` is kept as a trailing key segment.
- Built-in charset handling supports only `.utf8` and `.isoLatin1`; other
  encodings require a custom `encoder` or `decoder`.
- `EncodeOptions.encoder` is ignored when `encode: false`.
- Combining `encodeValuesOnly: true` and `encodeDotInKeys: true` encodes only
  dots in keys; values are otherwise handled by the values-only encoder path.
- `DecodeOptions.comma` parses simple comma-separated values, but does not
  decode nested map syntax such as `a={b:1},{c:d}`.
- `Qs.encode(nil)`, scalar roots, empty dictionaries, and empty containers
  generally produce an empty string.
- `NSNull()` is the explicit null-like value; `Undefined()` always omits a key.
  To round-trip bare-key nulls, encode and decode with `strictNullHandling:
  true`.
- Foundation and URL helper APIs may flatten, sort, or normalize query items.
  Prefer `Qs.decode` on the raw query string when qs-style nested or repeated
  values matter.

## Response Shape

For code-generation requests, answer with:

1. A short statement of assumptions, especially language, platform, package
   product, list format, null handling, charset, prefix handling, ordering, and
   whether input is trusted.
2. One concrete Swift or Objective-C snippet using `Qs.decode`, `Qs.encode`,
   `decodeAsync`, `decodeAsyncOnMain`, or the `QsObjC` bridge.
3. A brief explanation of only the options used.
4. A small verification example, such as an expected dictionary shape, expected
   query string, XCTest assertion, `#expect`, or Objective-C assertion.

Keep snippets application-oriented. Prefer public API imports from `QsSwift` or
`QsObjC`; do not ask users to import from `Internal` modules or implementation
files.

# QsSwift

<p align="center">
    <img src="https://github.com/techouse/qs-swift/raw/main/logo.png?raw=true" width="256" alt="QsSwift" />
</p>

A fast, flexible query string **encoding/decoding** library for Swift and [Objective-C](#objective-c).

Ported from [qs](https://www.npmjs.com/package/qs) for JavaScript.

[![SwiftPM version](https://img.shields.io/github/v/release/techouse/qs-swift?logo=swift&label=SwiftPM)](https://github.com/techouse/qs-swift/releases/latest)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftechouse%2Fqs-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/techouse/qs-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftechouse%2Fqs-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/techouse/qs-swift)
[![Docs (Swift)](https://img.shields.io/badge/Docs-QsSwift-blue)](https://techouse.github.io/qs-swift/qsswift/documentation/qsswift/) [![Docs (ObjC)](https://img.shields.io/badge/Docs-QsObjC-blue)](https://techouse.github.io/qs-swift/qsobjc/documentation/qsobjc/)
[![License](https://img.shields.io/github/license/techouse/qs-swift)](LICENSE)
[![Test](https://github.com/techouse/qs-swift/actions/workflows/test.yml/badge.svg)](https://github.com/techouse/qs-swift/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/techouse/qs-swift/graph/badge.svg?token=hk2eROAKOo)](https://codecov.io/gh/techouse/qs-swift)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/7ebd5d6b9de243d79f05fa995f2a2299)](https://app.codacy.com/gh/techouse/qs-swift/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/techouse)](https://github.com/sponsors/techouse)
[![GitHub Repo stars](https://img.shields.io/github/stars/techouse/qs-swift)](https://github.com/techouse/qs-swift/stargazers)

---

## Highlights

- Nested maps & lists: `foo[bar][baz]=qux` ⇄ `["foo": ["bar": ["baz": "qux"]]]`
- Multiple list formats (indices, brackets, repeat, comma)
- Dot-notation (`a.b=c`) and optional dot-encoding (setting `decodeDotInKeys` automatically enables dot notation)
- UTF‑8 and ISO‑8859‑1 charsets; optional charset sentinel (`utf8=✓`)
- Custom encoders/decoders, sorting, filtering, strict/null handling
- Deterministic ordering with `OrderedDictionary` (swift-collections)

---

## Requirements

- Swift **5.10+**
- Platforms: macOS **12+**, iOS **13+**, tvOS **13+**, watchOS **8+**

---

## Installation (Swift Package Manager)

### Xcode

- File → Add Package Dependencies…
- Enter: https://github.com/techouse/qs-swift
- Add the Qs library to your target.

### Package.swift

```swift
// in your Package.swift
dependencies: [
    .package(url: "https://github.com/techouse/qs-swift", from: "1.1.1")
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

---

## Quick start

```swift
import QsSwift

// Decode
let decoded: [String: Any] = try Qs.decode("foo[bar]=baz&foo[list][]=a&foo[list][]=b")
// decoded == ["foo": ["bar": "baz", "list": ["a", "b"]]]

// Encode
let encoded: String = try Qs.encode(["foo": ["bar": "baz"]])
// encoded == "foo%5Bbar%5D=baz"
```

---

## Usage

### Simple

```swift
// Decode
let obj: [String: Any] = try Qs.decode("a=c")
// ["a": "c"]

// Encode
let qs: String = try Qs.encode(["a": "c"])
// "a=c"
```

---

## Decoding

### Nested maps

```swift
try Qs.decode("foo[bar]=baz")
// ["foo": ["bar": "baz"]]

try Qs.decode("a%5Bb%5D=c")
// ["a": ["b": "c"]]

try Qs.decode("foo[bar][baz]=foobarbaz")
// ["foo": ["bar": ["baz": "foobarbaz"]]]
```

### Depth (default: 5)

Beyond the configured depth, the remainder is kept literally:

```swift
let r = try Qs.decode("a[b][c][d][e][f][g][h][i]=j")
// r["a"]?["b"]?["c"]?["d"]?["e"]?["f"]?["[g][h][i]"] == "j"
```

Set `strictDepth: true` to **throw** instead of collapsing the remainder when the limit is exceeded.

Override depth:

```swift
let r = try Qs.decode("a[b][c][d][e][f][g][h][i]=j", options: .init(depth: 1))
// r["a"]?["b"]?["[c][d][e][f][g][h][i]"] == "j"
```

### Parameter limit & ignoring `?`

```swift
try Qs.decode("a=b&c=d", options: .init(parameterLimit: 1))
// ["a": "b"]

try Qs.decode("?a=b&c=d", options: .init(ignoreQueryPrefix: true))
// ["a": "b", "c": "d"]
```

### Custom delimiters (string or regex)

```swift
try Qs.decode("a=b;c=d", options: .init(delimiter: StringDelimiter(";")))
// ["a": "b", "c": "d"]

let delim = try RegexDelimiter("[;,]")
try Qs.decode("a=b;c=d", options: .init(delimiter: delim))
// ["a": "b", "c": "d"]
```

### Dot notation & “decode dots in keys”

```swift
try Qs.decode("a.b=c", options: .init(allowDots: true))
// ["a": ["b": "c"]]

let r = try Qs.decode(
    "name%252Eobj.first=John&name%252Eobj.last=Doe",
    options: .init(decodeDotInKeys: true)
)
// ["name.obj": ["first": "John", "last": "Doe"]]
```

_Note:_ `decodeDotInKeys` implies `allowDots`; you don’t need to set both.

### Empty lists & duplicates

```swift
try Qs.decode("foo[]&bar=baz", options: .init(allowEmptyLists: true))
// ["foo": [], "bar": "baz"]

try Qs.decode("foo=bar&foo=baz")
// ["foo": ["bar", "baz"]]

try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .first))
// ["foo": "bar"]

try Qs.decode("foo=bar&foo=baz", options: .init(duplicates: .last))
// ["foo": "baz"]
```

### Charset & sentinel

```swift
try Qs.decode("a=%A7", options: .init(charset: .isoLatin1))
// ["a": "§"]

try Qs.decode(
    "utf8=%E2%9C%93&a=%C3%B8",
    options: .init(charset: .isoLatin1, charsetSentinel: true)
)
// ["a": "ø"]

try Qs.decode(
    "utf8=%26%2310003%3B&a=%F8",
    options: .init(charset: .utf8, charsetSentinel: true)
)
// ["a": "ø"]
```

### Interpret numeric entities (`&#1234;`)

```swift
try Qs.decode(
    "a=%26%239786%3B",
    options: .init(charset: .isoLatin1, interpretNumericEntities: true)
)
// ["a": "☺"]
```

_Heads-up:_ If you also enable `comma: true`, entity interpretation happens **after** comma processing. When you use list syntax like `a[]=...`, a comma-joined scalar stays a **single** element (e.g. `["1,☺"]`) inside the list, matching the library’s tests and cross-port behavior.

### Lists

```swift
try Qs.decode("a[]=b&a[]=c")
// ["a": ["b", "c"]]

try Qs.decode("a[1]=c&a[0]=b")
// ["a": ["b", "c"]]

try Qs.decode("a[1]=b&a[15]=c")
// ["a": ["b", "c"]]

try Qs.decode("a[]=&a[]=b")
// ["a": ["", "b"]]
```

Large indices become a map by default:

```swift
let r = try Qs.decode("a[100]=b")
// ["a": ["100": "b"]]
```

Disable list parsing:

```swift
let r = try Qs.decode("a[]=b", options: .init(parseLists: false))
// ["a": ["0": "b"]]
```

Mix notations:

```swift
let r = try Qs.decode("a[0]=b&a[b]=c")
// ["a": ["0": "b", "b": "c"]]
```

Comma-separated values:

```swift
let r = try Qs.decode("a=b,c", options: .init(comma: true))
// ["a": ["b", "c"]]
```

---

## Encoding

### Basics

```swift
try Qs.encode(["a": "b"])
// "a=b"

try Qs.encode(["a": ["b": "c"]])
// "a%5Bb%5D=c"
```

Disable URI encoding for readability:

```swift
try Qs.encode(["a": ["b": "c"]], options: .init(encode: false))
// "a[b]=c"
```

Values-only encoding:

```swift
let input: [String: Any] = [
    "a": "b",
    "c": ["d", "e=f"],
    "f": [["g"], ["h"]],
]
try Qs.encode(input, options: .init(encodeValuesOnly: true))
// "a=b&c[0]=d&c[1]=e%3Df&f[0][0]=g&f[1][0]=h"
```

Custom encoder:

```swift
let enc: ValueEncoder = { value, _, _ in
    // e.g. map "č" → "c", otherwise describe
    if let s = value as? String, s == "č" {
        return "c"
    }
    return String(describing: value ?? "")
}
try Qs.encode(["a": ["b": "č"]], options: .init(encoder: enc))
// "a[b]=c"
```

### List formats

```swift
// indices (default when encode=false)
try Qs.encode(["a": ["b", "c"]], options: .init(encode: false))
// "a[0]=b&a[1]=c"

// brackets
try Qs.encode(["a": ["b", "c"]], options: .init(listFormat: .brackets, encode: false))
// "a[]=b&a[]=c"

// repeat
try Qs.encode(["a": ["b", "c"]], options: .init(listFormat: .repeatKey, encode: false))
// "a=b&a=c"

// comma
try Qs.encode(["a": ["b", "c"]], options: .init(listFormat: .comma, encode: false))
// "a=b,c"
```

_Note:_ When you select `.comma`, you can set `commaRoundTrip = true` to append `[]` for single‑element lists so they can decode back into arrays. Set `commaCompactNulls = true` to drop `NSNull`/`nil` entries before joining (e.g., `["one", NSNull(), nil, "two"]` → `one,two`). If all entries are `NSNull`/`nil`, the key is omitted; if filtering leaves a single item and `commaRoundTrip = true`, `[]` is preserved.

### Nested maps and dot notation

```swift
try Qs.encode(["a": ["b": ["c": "d", "e": "f"]]], options: .init(encode: false))
// "a[b][c]=d&a[b][e]=f"

try Qs.encode(["a": ["b": ["c": "d", "e": "f"]]], options: .init(allowDots: true, encode: false))
// "a.b.c=d&a.b.e=f"
```

Encode dots in keys:

```swift
try Qs.encode(
    ["name.obj": ["first": "John", "last": "Doe"]],
    options: .init(allowDots: true, encodeDotInKeys: true)
)
// "name%252Eobj.first=John&name%252Eobj.last=Doe"
```

Empty lists, nulls, and other niceties:

```swift
// Allow empty lists (order preserved with OrderedDictionary input)
try Qs.encode(["foo": [Any](), "bar": "baz"], options: .init(allowEmptyLists: true, encode: false))
// e.g. "foo[]&bar=baz"

try Qs.encode(["a": ""])                         // "a="
try Qs.encode(["a": [Any]()])                    // ""
try Qs.encode(["a": ["b": [Any]()]])             // ""
try Qs.encode(["a": NSNull(), "b": Undefined()]) // "a="

try Qs.encode(["a": "b", "c": "d"], options: .init(addQueryPrefix: true))  // "?a=b&c=d"
try Qs.encode(["a": "b", "c": "d"], options: .init(delimiter: ";"))        // "a=b;c=d"
```

### Dates

```swift
let date = Date(timeIntervalSince1970: 0.007) // 7 ms since epoch

// Default ISO-8601 with millisecond precision (encode=false example)
try Qs.encode(["a": date], options: .init(encode: false))
// "a=1970-01-01T00:00:00.007Z"

// Custom serializer (epoch millis)
try Qs.encode(
    ["a": date],
    options: .init(
        dateSerializer: { d in String(Int((d.timeIntervalSince1970 * 1000.0).rounded())) },
        encode: false
    )
)
// "a=7"
```

### Sorting and filtering

```swift
// Sort keys
let sort: Sorter = { a, b in
    let la = String(describing: a ?? "")
    let lb = String(describing: b ?? "")
    return la.compare(lb).rawValue // -1/0/1
}
try Qs.encode(["a": "c", "z": "y", "b": "f"], options: .init(encode: false, sort: sort))
// "a=c&b=f&z=y"

// Function filter (drop/transform)
let date = Date(timeIntervalSince1970: 0.123) // 123 ms
let filter = FunctionFilter { prefix, value in
    switch prefix {
    case "b": return Undefined()
    case "e[f]":
        if let d = value as? Date {
            return Int((d.timeIntervalSince1970 * 1000.0).rounded())
        }
    case "e[g][0]":
        if let n = value as? NSNumber {
            return n.intValue * 2
        }
        if let i = value as? Int {
            return i * 2
        }
    default: break
    }
    return value
}

let input: [String: Any] = [
    "a": "b",
    "c": "d",
    "e": ["f": date, "g": [2]],
]
try Qs.encode(input, options: .init(encode: false, filter: filter))
// "a=b&c=d&e[f]=123&e[g][0]=4"

// Iterable filter (whitelist keys/indices)
try Qs.encode(["a": "b", "c": "d", "e": "f"], options: .init(encode: false, filter: IterableFilter(["a", "e"])))
// "a=b&e=f"
```

### RFC 3986 vs RFC 1738 (spaces)

```swift
try Qs.encode(["a": "b c"])                                   // "a=b%20c" (RFC 3986 default)
try Qs.encode(["a": "b c"], options: .init(format: .rfc3986)) // "a=b%20c"
try Qs.encode(["a": "b c"], options: .init(format: .rfc1738)) // "a=b+c"
```

---

## `nil`, `NSNull`, and `Undefined` (null semantics)

Query strings don’t have a native null concept, so Qs uses a few conventions to mirror “JSON-style” semantics as
closely as possible:

- `NSNull()` – use this to represent an explicit “null-like” value.
- `Undefined()` – a special sentinel provided by `Qs` to mean “omit this key entirely”.
- `""` (empty string) – a real, present-but-empty value.

### Encoding behavior (Swift → query string)

| Input value         | Default (`strictNullHandling: false`) | With `strictNullHandling: true` | With `skipNulls: true` |
|---------------------|---------------------------------------|---------------------------------|------------------------|
| `"foo"`             | `a=foo`                               | `a=foo`                         | `a=foo`                |
| `""` (empty string) | `a=`                                  | `a=`                            | `a=`                   |
| `NSNull()`          | `a=`                                  | `a` (no `=` sign)               | (omitted)              |
| `Undefined()`       | (omitted)                             | (omitted)                       | (omitted)              |

Examples:

```swift
try Qs.encode(["a": NSNull()])
// "a="

try Qs.encode(["a": NSNull()], options: .init(strictNullHandling: true))
// "a"               // bare key, no "="

try Qs.encode(["a": NSNull()], options: .init(skipNulls: true))
// ""                // key omitted

try Qs.encode(["a": Undefined()])
// ""                // always omitted, regardless of options
```

### Decoding behavior (query string → Swift)

| Input token | Default (`strictNullHandling: false`) | With `strictNullHandling: true` |
|-------------|---------------------------------------|---------------------------------|
| `a=`        | `["a": ""]`                           | `["a": ""]`                     |
| `a`         | `["a": ""]`                           | `["a": NSNull()]`               |

Examples:

```swift
try Qs.decode("a&b=")
// ["a": "", "b": ""]

try Qs.decode("a&b=", options: .init(strictNullHandling: true))
// ["a": NSNull(), "b": ""]
```

### How this maps to JSON libraries

- In **Foundation**'s **JSONSerialization**, `NSNull` is the conventional stand-in for JSON `null`.
  → In Qs, use `NSNull()` to mean a `null`-like value.
- In **Codable**/**JSONEncoder**, whether missing keys are emitted or omitted often depends on how your model is
  encoded (`encode` vs `encodeIfPresent`).
  → In `Qs`, use `Undefined()` to _always_ omit a key from the output.
- There is **[no native “null” in query strings]()**, so preserving a true “null round-trip” requires using:
    - `NSNull()` on `encode` and `strictNullHandling: true` (so it renders as a bare key), and
    - `strictNullHandling: true` on `decode` (so bare keys come back as `NSNull()`).

Round-trip tip:

```swift
// Encode with a null-like value:
let out = try Qs.encode(["a": NSNull()], options: .init(strictNullHandling: true))
// "a"

// Decode back to NSNull:
let back = try Qs.decode(out, options: .init(strictNullHandling: true))
// ["a": NSNull()]
```

If you simply want to drop keys when a value is not present, prefer `Undefined()` (or `skipNulls: true` when values are
`NSNull()`), rather than encoding `NSNull()` itself.

---

## API surface

- `Qs.decode(_:, options:) -> [String: Any]`
- `Qs.encode(_:, options:) -> String`
- `DecodeOptions` / `EncodeOptions` – configuration knobs
- `Duplicates` / `ListFormat` / `Format` – enums matching qs.js semantics
- `Undefined` – sentinel used by filters to omit keys

---

## Ordering notes

- If `options.sort != nil`, that comparator decides order.
- If `options.sort == nil` and `options.encode == false`, key order follows **input traversal** (use `OrderedDictionary`
  for stability).
- Arrays always preserve input order.

---

## Safety tips

- Keep `depth` and `parameterLimit` reasonable for untrusted inputs (defaults are sane).
- `allowEmptyLists`, `allowSparseLists`, and `parseLists` let you tune behavior for edge cases.
- Use `strictNullHandling` to differentiate `nil` (no `=`) from empty string (`=`).

---

## Bench (optional)

A tiny micro‑bench harness lives in `Bench/` (separate SPM package). It’s excluded from the main library.

```bash
cd Bench
make profile
```

---

## Objective-C

An Objective‑C bridge is included as [`QsObjC`](Sources/QsObjC) (facade + delegate-style hooks).
See the [QsObjC README](Sources/QsObjC/README.md) for installation, options, and examples. → [Docs](https://techouse.github.io/qs-swift/qsobjc/documentation/qsobjc/)

---

## Linux support

**Experimental** (Swift 6.0+)

On Linux, QsSwift uses [ReerKit](https://swiftpackageindex.com/reers/ReerKit)’s [`WeakMap`](https://github.com/reers/ReerKit/blob/main/Sources/ReerKit/Utility/Weak/WeakMap.swift)
to emulate [`NSMapTable.weakToWeakObjects()`](Sources/QsSwift/Internal/NSMapTable%2BLinux.swift) (weak keys **and** weak
values) for the encoder’s cycle‑detection side‑channel. This works around CoreFoundation APIs that aren’t available in
swift‑corelibs‑foundation on Linux.

#### Caveats

- Some tests that construct *self‑referential* `NSArray`/`NSDictionary` graphs are wrapped in `withKnownIssue` because
  swift‑corelibs‑foundation can crash when creating those graphs. (Apple platforms are unaffected.)
- CI includes an **experimental Ubuntu** job and is marked `continue-on-error` while Linux behavior stabilizes.

---

Special thanks to the authors of [qs](https://www.npmjs.com/package/qs) for JavaScript:

- [Jordan Harband](https://github.com/ljharb)
- [TJ Holowaychuk](https://github.com/visionmedia/node-querystring)

---

## Other ports


| Port                       | Repository                                                  | Package                                                                                                                                                                                       |
|----------------------------|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Dart                       | [techouse/qs](https://github.com/techouse/qs)               | [![pub.dev](https://img.shields.io/pub/v/qs_dart?logo=dart&label=pub.dev)](https://pub.dev/packages/qs_dart)                                                                                  |
| Python                     | [techouse/qs_codec](https://github.com/techouse/qs_codec)   | [![PyPI](https://img.shields.io/pypi/v/qs-codec?logo=python&label=PyPI)](https://pypi.org/project/qs-codec/)                                                                                  |
| Kotlin / JVM + Android AAR | [techouse/qs-kotlin](https://github.com/techouse/qs-kotlin) | [![Maven Central](https://img.shields.io/maven-central/v/io.github.techouse/qs-kotlin?logo=kotlin&label=Maven%20Central)](https://central.sonatype.com/artifact/io.github.techouse/qs-kotlin) |
| .NET / C#                  | [techouse/qs-net](https://github.com/techouse/qs-net)       | [![NuGet](https://img.shields.io/nuget/v/QsNet?logo=dotnet&label=NuGet)](https://www.nuget.org/packages/QsNet)                                                                                |
| Node.js (original)         | [ljharb/qs](https://github.com/ljharb/qs)                   | [![npm](https://img.shields.io/npm/v/qs?logo=javascript&label=npm)](https://www.npmjs.com/package/qs)                                                                                         |

---

## License

BSD 3‑Clause © [techouse](https://github.com/techouse)

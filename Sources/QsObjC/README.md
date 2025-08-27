# QsObjC — Objective‑C bridge for QsSwift

[![SwiftPM version](https://img.shields.io/github/v/release/techouse/qs-swift?logo=swift&label=SwiftPM)](https://github.com/techouse/qs-swift/releases/latest)
[![Docs](https://img.shields.io/badge/Docs-QsObjC-blue)](https://techouse.github.io/qs-swift/qsobjc/documentation/qsobjc/)
[![License](https://img.shields.io/github/license/techouse/qs-swift)](LICENSE)
[![Test](https://github.com/techouse/qs-swift/actions/workflows/test.yml/badge.svg)](https://github.com/techouse/qs-swift/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/techouse/qs-swift/graph/badge.svg?token=hk2eROAKOo)](https://codecov.io/gh/techouse/qs-swift)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/7ebd5d6b9de243d79f05fa995f2a2299)](https://app.codacy.com/gh/techouse/qs-swift/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/techouse)](https://github.com/sponsors/techouse)
[![GitHub Repo stars](https://img.shields.io/github/stars/techouse/qs-swift)](https://github.com/techouse/qs-swift/stargazers)

`QsObjC` exposes the Swift implementation of the popular `qs` query‑string library to Objective‑C. It mirrors the Swift
API closely and adds a few conveniences for Obj‑C style usage.

> ✅ **Platforms**: Apple platforms only (macOS, iOS, tvOS, watchOS). The bridge requires the Objective‑C runtime. On
> Linux or other non‑ObjC platforms, use `QsSwift` directly.

---

## Installation

### Swift Package Manager (Xcode)

1. **File → Add Packages…**
2. Enter your package URL.
3. Add the product **`QsObjC`** to your app/test targets.

### Swift Package Manager (Package.swift)

```swift
// Package.swift (consumer)
dependencies: [
  .package(url: "https://github.com/techouse/qs-swift", from: "1.1.1")
],
targets: [
  .target(
      name: "YourApp",
      dependencies: [
        .product(name: "QsObjC", package: "QsSwift") // Objective‑C bridge
      ]
  )
]
```

### Importing from Objective‑C

Use module import:

```objc
@import QsObjC;  // preferred
```

Or include the generated Swift header if you need it explicitly:

```objc
#import <QsObjC/QsObjC-Swift.h>
```

---

## TL;DR — Quick start

### Encode (NSDictionary → query string)

```objc
@import QsObjC;

NSDictionary *input = @{ @"a": @"b", @"c": @"d" };

QsEncodeOptions *opts = [QsEncodeOptions new];
opts.encode = NO; // for literal strings in examples/tests

NSError *err = nil;
NSString *qs = [Qs encode:input options:opts error:&err];
// qs => @"a=b&c=d"
```

### Decode (query string → NSDictionary)

```objc
NSError *err = nil;
NSDictionary *map = [Qs decode:@"a=b&c=d" options:nil error:&err];
// map => @{ @"a": @"b", @"c": @"d" }
```

### Convenience helpers

```objc
NSString *s1 = [Qs encodeOrEmpty:@{ @"a": @1 }];           // never nil → @"a=1"
NSString *s2 = [Qs encodeOrNil:nil];                       // nil input → nil (not an error)

NSDictionary *m1 = [Qs decodeOrEmpty:@"a=1"];              // never nil → @{ @"a": @"1" }
NSDictionary *m2 = [Qs decodeOrNil:@"oops" options:nil];   // nil on error (no throw)
NSDictionary *m3 = [Qs decodeOr:@"oops" options:nil default:@{ @"a": @"b" }]; // default fallback
```

> ⚠️ **Encoding order**: `NSDictionary` has no stable order. If you need deterministic order, set a sorter (see below)
> or build your data with an ordered container on the Swift side. Otherwise, the encoder may reorder keys.

---

## Encoding options (`QsEncodeOptions`)

```objc
QsEncodeOptions *o = [QsEncodeOptions new];
o.addQueryPrefix = YES;                 // ?a=b
o.delimiter = @";";                      // a=b;c=d

// Format: RFC 3986 (default) or RFC 1738
o.format = QsFormatRFC3986;             // or QsFormatRFC1738

// Keys/values percent-encoding control
o.encode = YES;                         // default YES; NO passes tokens as-is
o.encodeValuesOnly = NO;                // YES => leave keys untouched, only encode values

// Dots in keys (e.g. "user.name")
o.allowDots = NO;                       // enable dotted key‑path form when encoding
o.encodeDotInKeys = NO;                 // if YES, '.' in keys is percent‑encoded; requires allowDots = YES

// Arrays/lists
// Prefer listFormat; `indices` is kept for parity
//    QsListFormatBrackets => a[]=1&a[]=2
//    QsListFormatIndices  => a[0]=1&a[1]=2
//    QsListFormatRepeatKey=> a=1&a=2
//    QsListFormatComma    => a=1,2 (see commaRoundTrip)
o.listFormat      = QsListFormatIndices;
o.indices         = @(YES);              // only used when listFormat is nil (deprecated)
o.allowEmptyLists = NO;
o.commaRoundTrip  = NO;                  // append [] for singletons under .comma

// Nulls
// - strictNullHandling: key with nil value → "key" (no '=')
// - skipNulls: omit pairs whose value is NSNull / nil
o.strictNullHandling = NO;
o.skipNulls          = NO;

// Date and value encoding hooks
o.dateSerializerBlock = ^NSString *(NSDate *d) {
  return [@( (long long)floor([d timeIntervalSince1970]) ) stringValue];
};
o.valueEncoderBlock = ^NSString *(id value, NSNumber *charset, NSNumber *format) {
  // Return a *percent-encoded* token for the chosen charset
  return [NSString stringWithFormat:@"%@", value ?: @""];
};

// Deterministic key ordering
o.sortComparatorBlock = ^NSInteger(id a, id b) {
  NSString *sa = [NSString stringWithFormat:@"%@", a ?: @""]; // null-safe
  NSString *sb = [NSString stringWithFormat:@"%@", b ?: @""];
  NSComparisonResult r = [sa caseInsensitiveCompare:sb];
  if (r == NSOrderedSame) r = [sa compare:sb];
  return (r == NSOrderedAscending) ? -1 : (r == NSOrderedSame ? 0 : 1);
};
// or: o.sortKeysCaseInsensitively = YES; // built-in comparator

// Filtering
// - Function filter: return [QsUndefined new] to drop a key entirely
QsFunctionFilter *ff = [[QsFunctionFilter alloc] init:^id(NSString *key, id value) {
  if ([key isEqualToString:@"secret"]) return [QsUndefined new];
  return value;
}];
o.filter = [QsFilter function:ff];
// - Iterable filter: encode only these keys
//   o.filter = [QsFilter keys:@[@"a", @"b"]];
```

---

## Decoding options (`QsDecodeOptions`)

```objc
QsDecodeOptions *d = [QsDecodeOptions new];

d.ignoreQueryPrefix = YES;             // ignore leading '?'

d.allowDots = YES;                     // treat "a.b" like "a[b]" when enabled
// Tip: setting `decodeDotInKeys` also implies `allowDots` for safety.
// The bridge forwards both flags to the Swift core.

d.parseLists = YES;                     // parse a[0]=x&a[1]=y → arrays

d.duplicates = QsDuplicatesCombine;    // combine | first | last

// Limits and strictness

d.parameterLimit = 1000;                // must be > 0 (defensive cap on number of pairs)
d.listLimit      = 20;                  // max *index* to materialize as array; 0 ⇒ use a map for all indices
d.depth          = 5;                   // maximum bracket nesting (≥ 0)

d.strictDepth          = NO;            // YES: throw when over depth; NO (default): collapse the remainder into a literal key

d.strictNullHandling   = NO;            // if YES, keys with no value → NSNull instead of ""

d.throwOnLimitExceeded = NO;            // if YES, parameter/list/depth violations throw

// Custom scalar decoder (runs before interpretation)
d.valueDecoderBlock = ^id(NSString * token, NSNumber * charset) {
  return token; // return the decoded token as an object, or nil to keep the default
};
// Prefer the KEY/VALUE‑aware variant when you need context:
d.decoderBlock = ^id(NSString * token, NSNumber * charset, NSNumber * kind) {
  // kind: 0 = key, 1 = value
  if (kind.integerValue == 0) { return [NSString stringWithFormat:@"K:%@", token ?: @""]; }
  return token;
};

// Legacy two‑argument is still available (deprecated):
// d.legacyDecoderBlock = ^id(NSString * token, NSNumber * charset) { /* ... */ };

// Alternate delimiters
// String delimiters
//   d.delimiter = [QsDelimiter ampersand]; // default '&'
//   d.delimiter = [QsDelimiter semicolon];
// Regex delimiters
//   d.delimiter = [QsDelimiter commaOrSemicolon];

> **Note (ISO‑8859‑1 + `interpretNumericEntities` + `comma`)**: When you explicitly use `a[]=` with `comma:YES`, a token like `a[]=1,&#9786;` decodes as a **single element** array `[@"1,☺"]` — the scalar is kept together and numeric entities are interpreted. This matches the Swift port’s semantics and avoids surprising splits when brackets specify the array.
```

### Error handling

All throwing APIs fill `NSError **` with domains and codes that mirror Swift:

- **Encode**: `QsEncodeErrorInfo.domain` with code `QsEncodeErrorCodeCyclicObject` when a cycle is detected.
- **Decode**: `QsDecodeErrorInfo.domain` with codes:
    - `QsDecodeErrorCodeParameterLimitNotPositive`
    - `QsDecodeErrorCodeParameterLimitExceeded`
    - `QsDecodeErrorCodeListLimitExceeded`
    - `QsDecodeErrorCodeDepthExceeded`

```objc
NSError *err = nil;
NSMutableDictionary *m = [NSMutableDictionary new];
m[@"self"] = m; // cycle
NSString *s = [Qs encode:m options:nil error:&err];
if (!s && [err.domain isEqualToString:QsEncodeErrorInfo.domain] && err.code == QsEncodeErrorCodeCyclicObject) {
  // handle/expect cycles here
}
```

---

## Async helpers

The bridge offers callback‑style async wrappers that are `@Sendable` safe and optionally hop back to the main thread.

```objc
// Main‑thread callback
[Qs encodeAsyncOnMain:@{@"a": @1} options:nil completion:^(NSString * _Nullable s, NSError * _Nullable err) {
// UI‑safe
}];

[Qs decodeAsyncOnMain:@"a=1" options:nil completion:^(NSDictionary * _Nullable map, NSError * _Nullable err) {
// UI‑safe
}];

// Background callback (no hop to main)
[Qs encodeAsync:@{@"a": @1} options:nil completion:^(NSString * _Nullable s, NSError * _Nullable err) {
// background
}];

[Qs decodeAsync:@"a=1" options:nil completion:^(NSDictionary * _Nullable map, NSError * _Nullable err) {
}];
```

---

## Working with key order

- `NSDictionary` doesn’t guarantee enumeration order. For human‑readable output, set a custom sorter via
  `sortComparatorBlock` or `sortKeysCaseInsensitively`.
- If you use Swift’s `OrderedDictionary` on the Swift side, the bridge preserves insertion order.

> In tests we sometimes create ordered shapes explicitly; in typical app code, prefer the sorter to avoid surprises.

---

## FAQ

- **Q: Can I use `QsObjC` on Linux?**
  A: No. Use `QsSwift` on Linux. The Objective‑C bridge requires Apple’s Obj‑C runtime.

- **Q: How do I drop a key during encoding?**
  A: In a `QsFunctionFilter` block, return `[QsUndefined new]`.

- **Q: Why doesn’t my output key order match input order?**
  A: `NSDictionary` is unordered. Provide a sorter or build ordered data.

- **Q: What’s the difference between `allowDots` and `encodeDotInKeys`?**
  A: `allowDots` lets dots behave like dots (vs. bracket‑style); `encodeDotInKeys` forces `.` to be percent‑encoded. The
  bridge forwards both flags to the Swift core.

---

## License

BSD 3‑Clause © [techouse](https://github.com/techouse)

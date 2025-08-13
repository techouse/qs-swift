---
name: Bug report
about: The library crashes, produces incorrect encoding/decoding, or behaves unexpectedly.
title: ''
labels: bug
assignees: techouse
---

<!--
  Since this is a port of `qs`, please check the original repo for related issues:
  https://github.com/ljharb/qs/issues
  If you find a relevant issue or spec note, please link it here.
-->

## Summary

<!-- A clear and concise description of what the bug is. -->

## Steps to Reproduce

<!-- Include full steps so we can reproduce the problem. Prefer a minimal repro. -->

1. ...
2. ...
3. ...

**Expected result**
<!-- What did you expect to happen? -->

**Actual result**
<!-- What actually happened? Include exact output / string values where relevant. -->

## Minimal Reproduction

> The simplest way is a single unit test that fails.
> Create a tiny SwiftPM package or add a test to your project demonstrating the issue.

<details>
<summary>Failing Swift test (Swift Testing with #expect)</summary>

```swift
import Testing
import Qs

@Test
func repro() throws {
    // Replace with the minimal input that fails:
    let decoded = try Qs.decode("a[b]=1")
    // Expectation mirrors JS `qs` behavior
    #expect((decoded as NSDictionary) == ["a": ["b": "1"]] as NSDictionary)
}
```
</details>

If the issue only appears when **encoding**, add the minimal input + options used:

```swift
import Qs

let out = try Qs.encode(["a": ["x", "y"]], options: EncodeOptions(encode: false))
print(out) // <-- paste the actual output and the expected output in the issue
```

If the issue only appears on **Apple platforms (iOS/tvOS/watchOS)**, please provide a platform-focused repro (see “Apple platform details” below).

## Logs

Please include relevant logs:

- SwiftPM build + tests (CLI):
  ```bash
  swift build -v
  swift test -v --enable-code-coverage
  ```

- If you created a small demo package, include the full console output from the failing run.

- If a specific input string causes the issue, paste that exact string together with the actual and expected decoded/encoded structures.

<details>
<summary>Console output</summary>

```
# paste here
```
</details>

## Environment

- OS: <!-- e.g., macOS 14.5 / Ubuntu 22.04 / Windows 11 (via Swift toolchain) -->
- Swift: output of `swift --version`
- Xcode: <!-- e.g., 15.4 (if applicable) -->
- SwiftPM: <!-- e.g., 5.10 (or "via Xcode") -->
- QsSwift version: <!-- e.g., 0.1.0 -->
- Platform targets: <!-- e.g., iOS 13+ / macOS 12+ / tvOS 13+ / watchOS 8+ -->
- Charset in use (if relevant): <!-- UTF-8 / ISO-8859-1 -->
- Apple Silicon? Rosetta? (if relevant): <!-- yes/no -->

### Dependency snippet (SwiftPM)

```text
# In your Package.swift (dependencies section)
dependencies: [
    // ...
    .package(url: "https://github.com/techouse/QsSwift.git", from: "<version>")
]
```

```text
# In your Package.swift (targets section)
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "QsSwift", package: "qs-swift")
    ]
)
```

> If you use additional encoders/decoders or custom options, please mention and show their configuration.

## Apple platform details (if applicable)

- Xcode version:
- iOS/tvOS/watchOS deployment target:
- Device/Simulator + OS version:
- Repro steps (scheme and command):
  ```bash
  # Example: run iOS unit tests on a simulator
  xcodebuild -scheme Qs -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' test | xcpretty
  ```

- Minimal sample preferred: a tiny app/module with one failing unit test or an instrumentation-style repro.

## Is this a regression?

- Did this work in a previous version of QsSwift? If so, which version?

## Additional context

- Links to any related `qs` JavaScript issues/spec notes:
- Any other libraries involved (HTTP clients, frameworks, etc.) and versions:
- Edge cases (e.g., very deep nesting, extremely large strings, ISO-8859-1 with numeric entities, RFC1738 vs RFC3986 spaces, Date/ISO8601 serialization, comma list format, etc.):

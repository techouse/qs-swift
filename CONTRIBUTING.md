# Contributing to `QsSwift`

Thanks for your interest in improving QsSwift! This project welcomes PRs, issues, and discussion.
Please read this guide before contributing.

> A friendly reminder: this project follows a Code of Conduct. See `CODE-OF-CONDUCT.md`.

---

## Supported toolchain

- Swift: 5.10+ (see `// swift-tools-version: 5.10` in Package.swift)
- Package manager: Swift Package Manager (SPM)
- Platforms (minimums):
  - macOS 12+
  - iOS 13+
  - tvOS 13+
  - watchOS 8+
- IDE: Xcode 15.x (or newer compatible with Swift 5.10) or any editor with Swift toolchain

If you find breakage on newer Swift/Xcode versions, please open an issue with reproduction details.

---

## Getting started

```bash
# Clone
git clone https://github.com/techouse/QsSwift.git
cd QsSwift

# Build (debug)
swift build

# Run the full test suite (debug)
swift test

# Run a single test case or method (XCTest filter)
# by test case type name
swift test --filter QsTests.EncodeTests
# by test method name
swift test --filter QsTests.EncodeTests/testArrayFormatComma

# Build (release, without tests)
swift build -c release
```

### Xcode

- Open the package directly: `open Package.swift` (Xcode 15+)
- Or generate an Xcode project: not required; Xcode opens SwiftPM packages natively
- Scheme: Qs (library) and QsTests (tests)

### Benchmarks (optional)

There is a separate benchmark package under `Bench/`.

```bash
cd Bench
swift build -c release
.build/release/QsBench list        # default scenario
N=5000 .build/release/QsBench deep # deep key path scenario
```

See `Bench/README.md` for A/B profiling and `make profile` helpers.

---

## Code style & formatting

This repository does not enforce a specific formatter in CI yet. If you want to propose one, open a PR or discussion first. Popular choices:

- SwiftFormat (nicklockwood/SwiftFormat)
- SwiftLint (realm/SwiftLint)
- swift-format (apple/swift-format)

Guidelines until a tool is adopted:

- 4‑space indentation, meaningful names, small and focused functions.
- Keep hot-path methods allocation-light.
- Prefer simple loops over heavyweight Regex for tight parsing paths.
- Avoid unnecessary bridging to Foundation types in hot code.
- Favor inout mutation where it reduces copying and remains clear.

If you add formatter/linter tooling in a PR, document how to run it (e.g., `make format`, `swift format`, or `swiftlint`) and keep configs in sync with Xcode/SwiftPM.

---

## Tests

We use XCTest for unit tests. When you change code paths that touch parsing or encoding, please add or update tests.

Common commands:

- Run all tests: `swift test`
- Fail fast: `swift test --filter` to scope down to the failing area
- With verbose logs: `swift test -v`
- Generate an HTML report in Xcode: run tests via the Test action (⌘U) and open the report navigator

### Coverage

You can get coverage from the CLI:

```bash
# Quick coverage (debug)
swift test --enable-code-coverage

# Helper script that exports LCOV and (optionally) HTML
./scripts/coverage.sh          # writes coverage/info.lcov
./scripts/coverage.sh --html   # also generates coverage/html/index.html and opens it
```

Notes:
- The script requires `llvm-cov` (Xcode CLT on macOS; `llvm` on Linux). For HTML export, install `lcov` (e.g., `brew install lcov`).

---

## Project layout (high level)

```
Sources/Qs/
  Qs.swift                        # Public API root
  Qs+Decode.swift                 # Public decode entry points
  Qs+DecodeConvenience.swift      # Convenience decode helpers
  Qs+Encode.swift                 # Public encode entry points
  Qs+EncodeConvenience.swift      # Convenience encode helpers
  Constants/HexTable.swift        # Hex table for fast encoding
  Enums/, Models/                 # Options, enums, small value types
  Internal/
    Decoder.swift                 # Internal decoding helpers
    Encoder.swift                 # Internal encoding helpers
    Utils.swift                   # Core helpers, escaping/unescaping, merge, etc.
Tests/QsTests/
  *Tests.swift                    # XCTest cases mirroring qs behavior
Bench/
  ...                             # Separate Swift package for microbenchmarks
```

---

## Compatibility with JS `qs`

This port aims to mirror the semantics of `qs` (https://github.com/ljharb/qs), including edge cases.
If you notice divergent behavior, please:

1. Add a failing test that demonstrates the difference.
2. Reference the `qs` test or behavior you expect.
3. Propose a fix, or open a focused issue.

---

## Performance notes

- Hot paths (splitting parameters, bracket scanning, entity interpretation) should avoid Regex where simple loops suffice.
- Prefer `reserveCapacity` on arrays/dictionaries and reuse buffers.
- Avoid creating intermediate dictionaries/arrays inside tight loops.
- Watch algorithmic complexity (e.g., nested scans, deep key assembly).
- Use `@inline(__always)`/`@inlinable` judiciously where profiling shows benefit (benchmarks can help validate).
- Be mindful of copy-on-write costs; use `inout` where it simplifies and reduces copies.

If you submit perf changes, include a short note and—if possible—a microbenchmark using `Bench/`.

---

## Submitting a change

1. Open an issue first for big changes to align on approach.
2. Small, focused PRs are easier to review and land quickly.
3. Add tests that cover new behavior and edge cases.
4. Keep the public API stable unless we agree on a version bump.
5. Changelog entry (in the PR description is fine) for user-visible changes.

### Commit/PR style

- Clear, descriptive commits. Conventional Commits welcome but not required.
- Reference issues as needed, e.g., “Fixes #123”.
- Prefer present tense: “Add X”, “Fix Y”.

### Branch naming

Use a short, descriptive branch: `fix/latin1-entities`, `feat/weakmap-sidechannel`, etc.

---

## Releasing (maintainers)

1. Prepare release notes (Added/Changed/Fixed; document behavior differences if any).
2. Ensure `swift test` passes in clean state (optionally, run coverage script).
3. Tag a semantic version: `git tag -a vX.Y.Z -m "Release vX.Y.Z" && git push --tags`.
4. Create a GitHub Release and attach notes.
5. Update README usage examples if coordinates or API changed.

---

## Security

If you believe you’ve found a vulnerability, please do not open a public issue.
See `SECURITY.md` for the responsible disclosure process.

---

## Questions?

Open a discussion or issue with as much detail as possible (input, expected vs actual output, environment).
Thanks again for helping make QsSwift solid and fast!

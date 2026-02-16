# Repository Guidelines

## Project Structure & Module Organization
QsSwift is a SwiftPM package defined in `Package.swift`. The core implementation sits in `Sources/QsSwift`, segmented by feature (e.g. `Qs+Encode.swift`, `Internal/Encoder.swift`). The ObjC bridge lives in `Sources/QsObjC`, sharing the same tests where the bridge surface matters. Unit tests sit under `Tests/QsSwiftTests` and `Tests/QsObjCTests`, while integration coverage for ObjC hosts inside `ObjCE2ETests`. Benchmarks and diagnostics live in `Bench/` and `Tools/QsSwiftComparison/`; documentation assets land inside `docs/`, and helper scripts (coverage, automation) live in `scripts/`.

## Build, Test, and Development Commands
Run `swift build` or `make build` for a debug build; `make build-release` produces the optimized artefacts. Execute `make test` (or `SWIFT_DETERMINISTIC_HASHING=1 swift test -q`) for the primary SwiftPM test suites (`swift-testing` in `Tests/QsSwiftTests` and `Tests/QsObjCTests`), and `make test-release` for release-mode validation. To inspect coverage, use `bash scripts/coverage.sh` (add `--html` for a browsable report). The comparison utility can be exercised with `swift run QsSwiftComparison --help` to spot regressions against the JS `qs` fixtures.

## Coding Style & Naming Conventions
Follow Swift’s standard casing: `UpperCamelCase` types, `lowerCamelCase` methods/properties, `SCREAMING_SNAKE_CASE` for static lookup tables. Indent with four spaces and keep files focused; slice APIs into extensions that mirror the file naming pattern already in `Sources/QsSwift`. Favor value semantics, avoid unnecessary Foundation bridging on hot paths, and keep allocation-light loops instead of regexes. No formatter runs in CI, so stage only intentional whitespace edits.

## Testing Guidelines
SwiftPM tests in `Tests/QsSwiftTests` and `Tests/QsObjCTests` use `apple/swift-testing` (`@Test`, `#expect`), while `ObjCE2ETests` uses XCTest. Mirror new behavior with `*Tests.swift` companions under the matching module directory, and keep test names descriptive (`encode_arrayFormatComma` or `testArrayFormatComma`). For ObjC additions, add cases in `Tests/QsObjCTests` and, where needed, `ObjCE2ETests`. Run `swift test --filter TypeName/testCase` to iterate quickly. Aim to keep coverage steady; regenerate LCOV output via `scripts/coverage.sh --release` before large merges.

## Commit & Pull Request Guidelines
Commits in this repo stay focused, present-tense, and often adopt emoji prefixes (`:memo:`, `:arrow_up:`); match that style when possible. Reference issues inline (`Fixes #123`) and update docs or changelog entries when behavior shifts. PRs should describe the change, list validation (`swift test`, coverage steps), link any benchmarks, and attach screenshots for tooling/UI-affecting work. Keep branches short (`feat/`, `fix/`), request reviews early, and observe the Code of Conduct and `SECURITY.md` escalation channel.

# Copilot Instructions for QsSwift

These guidelines help AI coding agents work effectively in this repository.
Keep responses concise, follow established patterns, and prefer making the change directly over suggesting it.

## 1. Project Overview
- Library: Query string encode/ decode (Swift + Objective‑C bridge) – a faithful port of the JS `qs` library.
- Targets: `QsSwift` (core), `QsObjC` (Objective‑C bridge), `QsSwiftComparison` (fixture comparison tool), `Bench/` (separate micro‑bench package).
- Core features: nested map/list parsing, multiple list formats, dot-notation, charset handling, custom sorting/filtering, null semantics (NSNull vs Undefined), deterministic ordering via `OrderedDictionary`.

## 2. Architecture & Key Files
- `Sources/QsSwift/Qs.swift` – public façade: `encode` / `decode` plus options types.
- `Sources/QsSwift/Internal/` – parsing + encoding engine (hot paths; avoid unnecessary allocations, no regex unless already present).
- `Sources/QsObjC/` – thin wrappers translating ObjC types (`NSDictionary`, `NSArray`, blocks) into Swift equivalents; mirrors Swift options (`QsDecodeOptions`, `QsEncodeOptions`).
- `Tests/QsSwiftTests/Fixtures/Data/EndToEndTestCases.swift` – canonical encode/decode round‑trip shapes.
- `Tools/QsSwiftComparison/` – compares output with upstream JS fixtures.
- Linux-only shim: `NSMapTable+Linux.swift` + ReerKit for weak map emulation.

## 3. Conventions
- Keep option structs lightweight, value‐semantics in Swift; bridge classes (`final class`) on ObjC side.
- Preserve deterministic ordering by using `OrderedDictionary` in fixtures & tests. Do NOT replace with plain `[String: Any]` if ordering matters.
- Avoid adding global state. Prefer passing options explicitly.
- Null handling: `NSNull()` represents a null-like value; `Undefined()` means “omit key entirely”. Respect `strictNullHandling` and `skipNulls` flags.
- Sorting: if `sort` closure is nil and `encode=false`, retain traversal order. When adding new traversal logic, maintain stability.

## 4. Performance Notes
- Hot loops avoid bridging to Foundation unless required. Minimize temporary arrays/strings.
- Large index handling: indices above `listLimit` turn arrays into maps; keep logic consistent when modifying.
- Depth & parameter limits must remain O(length(query)) without quadratic regressions.

## 5. Adding Features
When implementing a new option or behavior:
1. Update Swift option structs (`EncodeOptions`, `DecodeOptions`).
2. Mirror in ObjC bridge classes (`QsEncodeOptions`, `QsDecodeOptions`) only if applicable to ObjC users.
3. Add unit tests in both `QsSwiftTests` and (if bridged) `QsObjCTests`.
4. Update README sections and docs comments (DocC) if user-visible.
5. Keep changes allocation-neutral where possible; benchmark if touching tight loops.

## 6. Testing Guidelines
- Run `make test` (exports `SWIFT_DETERMINISTIC_HASHING=1`). Release validation: `make test-release`.
- Add new fixtures beside similar ones; for end-to-end cases, mutate `EndToEndTestCases.swift` only with `OrderedDictionary`.
- Prefer explicit assertion helpers over vague equality when validating ordering or null semantics.
- For ObjC tests use `QsObjCTests` and ensure key ordering expectations either avoid relying on `NSDictionary` enumeration order or explicitly sort.

## 7. Bench & Comparison
- Use `Bench/` for micro performance checks (optional). Run with `swift build -c release` inside `Bench/`.
- Cross‑port parity: `swift run QsSwiftComparison` to diff against JS fixture outputs when changing core semantics.

## 8. ObjC Bridge Specifics
- Async helpers: avoid introducing additional captures that trigger Sendable warnings; keep closures minimal.
- Blocks map to Swift closures; unwrap and pass through without extra allocations.
- When exposing new enums or option flags, keep ObjC naming (`QsListFormatIndices`, etc.) consistent with existing cases.

## 9. Error Handling
- Do not swallow errors inside core encode/decode; propagate as thrown Swift errors or `NSError` in ObjC convenience wrappers.
- Maintain existing error domains/codes (see ObjC README) when adding new failure modes.

## 10. Style & Hygiene
- 4-space indentation, keep focused files (extensions per concern).
- Avoid broad reformatting; only touch diff‑related lines.
- Doc comments: concise, mention option interactions (e.g. `decodeDotInKeys` implies `allowDots`).

## 11. Pull Request Expectations
- Include: summary, validation steps (`swift test`, any comparison or bench data if perf‑related), updated docs for user-facing changes.
- Keep commits small & present‑tense (emoji prefixes optional: :memo:, :sparkles:, :wrench:).

## 12. Quick Command Reference
- Build: `swift build` / release: `swift build -c release`
- Tests: `make test` / release tests: `make test-release`
- Coverage: `bash scripts/coverage.sh --html`
- Comparison tool: `swift run QsSwiftComparison --help`
- Bench profile: `(cd Bench && make profile)`

## 13. Safe Assumptions for Agents
- Assume Swift 5.10+ / tools-version 6.1 environment.
- Objective‑C bridge only on Apple platforms (`QS_OBJC_BRIDGE` flag guards code).
- Ordered structures in tests are intentional—preserve them.

If something is unclear (e.g. adding a new delimiter strategy), surface a concise question with suggested options.

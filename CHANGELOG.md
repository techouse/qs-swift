## 1.3.0

- [FIX] harden deep encoding paths with iterative fallback to prevent stack overflows on very deep nested payloads, while preserving cycle detection and deterministic traversal behavior.
- [FIX] improve scalar/optional encoding correctness: properly unwrap `Optional.some`, preserve `Data` stringification behavior (including malformed UTF-8 visibility), and keep set-like scalar values on the scalar encode path.
- [FIX] align comma-list decode overflow behavior with `qs@6.14.2`: non-throwing first-occurrence overflows now fall back to indexed overflow maps, preserve explicit `[]` list-of-lists semantics, and apply decoder/entity transforms without shape loss.
- [FIX] add overflow safety guards in decode materialization and list-length accounting (safe overflow arithmetic, bounded dense materialization floor, and metadata/key max-index reconciliation).
- [FIX] make deep dictionary merges iterative to avoid recursion blowups and preserve overflow metadata/max-index reconciliation in nested merge scenarios.
- [FIX][ObjC] normalize bridged decode/encode options (charset, depth, parameterLimit, dot flags) and preserve nested filter traversal when ObjC function filters return the original value object.
- [FIX][Linux] extend `NSMapTable` shim with strong-to-strong storage semantics and safer weak-mode behavior; bump ReerKit dependency to `1.2.5`.
- [TEST] expand Swift + ObjC regression coverage for deep encode/decode paths, comma overflow edge cases, merge overflow metadata behavior, ObjC async decode error delivery, and ObjC option/model bridging.
- [CI] add Address Sanitizer deep-regression checks for Swift and ObjC encode paths on macOS runners; enable previously experimental matrix entries for regular validation.
- [CHORE] update JS comparison fixture dependency to `qs@6.14.2` and refresh contributor/agent testing guidance docs.

## 1.2.1

- [FIX] enhance Utils with overflow handling and list limit enforcement

## 1.2.0

- [FEAT] add `EncodeOptions.commaCompactNulls` to drop `NSNull`/`nil` values when producing comma lists

## 1.1.6

- [FEAT] add support in `QsBridge._bridgeInputForEncode` for handling `OrderedDictionary<AnyHashable, Any>`, converting keys to deterministic string representations to ensure consistent bridging of heterogeneous key types
- [FIX] refine array handling in `Utils.compactValue` to better tolerate both [Any] and [Any?] array shapes, ensuring correct compaction and bridging of arrays with optional elements and nested containers
- [CHORE] increase test coverage

## 1.1.5

- [FEAT] add experimental Linux support

## 1.1.4

- [FIX] remove redundant imports
- [CHORE] add exclusion of unnecessary files in QsSwiftComparison target
- [CHORE] update build action entries and test action configurations for `QsSwiftComparison` scheme

## 1.1.3

- [CHORE] refactor code and improve variable naming for clarity and consistency
- [CHORE] add QsSwift <-> qs.js comparison tests

## 1.1.2

- [FEAT] Introduce `DecodeKind` to distinguish **key** vs **value** decoding; add Objective‑C mirror `QsDecodeKind`.
- [FEAT] Unify scalar decoding via `ScalarDecoder` (KEY/VALUE‑aware). Add `DecodeOptions.decodeKey` / `decodeValue` helpers.
- [DEPRECATION] Deprecate `ValueDecoder`, legacy decoder, and `getDecoder(_:charset:)`. The Obj‑C bridge provides a temporary `legacyDecoderBlock`, but `decoderBlock` now takes precedence.
- [FEAT][ObjC] Add KEY/VALUE‑aware `decoderBlock` to `QsDecodeOptions`; Swift bridging prefers it over `valueDecoderBlock`.
- [FIX] Dot‑in‑keys decoding: correct handling for top‑level encoded/literal dots, bracket depth limits, leading/trailing/double dots; safer key‑segment splitting; list‑parsing guardrails; preserve `depth=0` semantics.
- [FIX] Query parsing: only strip a leading `?`; normalize encoded brackets **only inside key slices**; correctly detect empty bracketed keys (including `%5B%5D`); treat empty bracket keys as `"0"` when list parsing is disabled; list‑limit checks consider current size and throw when exceeded.
- [FIX] Bridging & cycles: robust identity tracking for Foundation containers (maps & arrays); fix crashes with cyclic arrays; handle non‑`AnyHashable` dictionary keys; maintain path‑local `seen` sets.
- [FIX] Custom decoder: preserve element‑level `nil` as `NSNull` inside arrays; charset mock updated to `ScalarDecoder` signature.
- [TEST] Comprehensive Swift & Obj‑C tests for dot decoding, depth behavior, decoder precedence, key‑segment splitting, charset handling, async delivery, and convenience helpers; added parity tests.
- [DOCS] Clarify dot semantics, depth rules, decoder precedence, and ISO‑8859‑1 + `interpretNumericEntities` behavior with comma lists.
- [CI] Add Objective‑C end‑to‑end workflow with coverage upload; crash‑log collection script; faster, more reliable macOS builds (caching, signing/retry, safer symlink handling); streamlined permissions.

## 1.1.1

- [FEAT][ObjC] add Objective-C bridge
- [CHORE] various bug fixes and improvements

## 1.1.0

- [CHORE] Rename package to QsSwift

## 1.0.0

- [CHORE] Initial release of the project.

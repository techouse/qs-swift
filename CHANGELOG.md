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

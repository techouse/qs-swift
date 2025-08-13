/// Top-level namespace for the qs encoder/decoder.
///
/// This enum is intentionally empty and used purely as a *namespace*.
/// All APIs live in extensions split across files:
///   - `Qs+Encode.swift`              → `encode(...)`
///   - `Qs+Decode.swift`              → `decode(...)`, `decodeAsync(...)`
///   - `Qs+EncodeConvenience.swift`   → convenience wrappers
///   - `Qs+DecodeConvenience.swift`   → convenience wrappers
///
/// Why an empty enum?
/// - Prevents instantiation and stored state.
/// - Groups static APIs under a single, stable symbol.
/// - Lets the implementation be factored across files without leaking internals.
///
/// Concurrency & runtime notes:
/// - Decoding offers async variants to avoid blocking and to mitigate deep
///   destructor recursion on some Swift runtimes (see `Utils.dropOnMainThread`).
/// - APIs are pure w.r.t. input; no global state is mutated.
///
/// Usage:
///     let qs = try Qs.encode(["a": "b"])
///     let map = try Qs.decode("a=b")
///
/// Keep `Qs` as a static namespace only—don’t add stored properties or nested state here.
public enum Qs {}

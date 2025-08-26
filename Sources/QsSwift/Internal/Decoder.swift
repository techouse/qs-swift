/// A helper for decoding query strings into structured data.
///
/// Pipeline overview:
/// 1. `parseQueryStringValues` splits and decodes the raw string into an ordered
///    flat view of `key → value` pairs (values may be `String`, arrays when `comma`,
///    or `NSNull` for strict nulls).
/// 2. For each pair, `parseKeys` turns a bracket/dot path into segments (with
///    depth handling and **remainder wrapping**). If the key contains more bracket
///    groups than `depth` allows and `strictDepth == false`, the unprocessed
///    remainder is collapsed into **one synthetic trailing segment**; if an
///    unterminated bracket group is encountered, the raw remainder is wrapped
///    the same way. With `strictDepth == true`, only *well‑formed* overflow throws.
/// 3. The caller merges fragments into the final object.
@usableFromInline
internal enum Decoder {}

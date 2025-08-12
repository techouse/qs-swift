/// How to handle repeated keys in the input, e.g. `foo=1&foo=2`.
///
/// QS follows these semantics:
/// - `.combine`: keep **all** values. The first occurrence is stored as a scalar; the
///   second (and later) occurrences promote the value to an array, preserving order,
///   e.g. `"foo=1&foo=2"` → `["foo": ["1", "2"]]`.
/// - `.first`: keep **only the first** value; subsequent duplicates are ignored,
///   e.g. `"foo=1&foo=2"` → `["foo": "1"]`.
/// - `.last`: keep **only the last** value; earlier ones are overwritten,
///   e.g. `"foo=1&foo=2"` → `["foo": "2"]`.
public enum Duplicates: CustomStringConvertible {
    /// Combine duplicate keys into a single key with an array of values (order preserved).
    case combine

    /// Keep the first value and ignore subsequent duplicates.
    case first

    /// Keep the last value and overwrite earlier ones.
    case last

    /// Human-readable label for logging/debugging.
    public var description: String {
        switch self {
        case .combine: return "combine"
        case .first: return "first"
        case .last: return "last"
        }
    }
}

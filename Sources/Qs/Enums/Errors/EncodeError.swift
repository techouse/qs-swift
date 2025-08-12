/// Errors that may be thrown by the query-string encoder.
///
/// The encoder walks the input object graph (dictionaries, arrays, nested values) and
/// will fail fast if it encounters a reference cycle to avoid infinite recursion.
///
/// Typical causes:
/// - A dictionary or array that (directly or indirectly) contains itself.
/// - Two containers that reference each other through intermediate values.
///
/// Example:
/// ```swift
/// var a: [String: Any] = [:]
/// a["self"] = a            // cycle
/// try Qs.encode(a)         // throws EncodeError.cyclicObject
/// ```
///
/// How to fix:
/// - Break the cycle before encoding (serialize to an acyclic DTO).
/// - Or provide a custom `filter`/`encoder` in `EncodeOptions` that drops or replaces
///   the cyclic portions (e.g., replace an object with an ID).
public enum EncodeError: Error, Equatable, CustomStringConvertible {
    /// The input object graph contains a reference cycle (e.g., a dictionary/array
    /// that refers to itself), which would cause infinite recursion during encoding.
    case cyclicObject

    /// Human-readable description useful in tests and logs.
    public var description: String {
        switch self {
        case .cyclicObject:
            return "Cyclic object graph detected during encoding."
        }
    }
}

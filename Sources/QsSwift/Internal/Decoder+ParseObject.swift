import Foundation

extension QsSwift.Decoder {
    /// Builds a nested structure from a chain of key segments, inserting `value` at the leaf.
    ///
    /// Handles:
    /// - "[]" segments:
    ///   - When `parseLists == true`:
    ///     * `allowEmptyLists` → `[]` for empty or `nil` (when `strictNullHandling`)
    ///     * otherwise wraps scalars into single‑element lists
    ///   - When `parseLists == false`: treat as a dictionary with string key "0"
    /// - Numeric bracket segments like "[0]":
    ///   - When `parseLists == true` and index ≤ `listLimit`, produces a list shell filled with
    ///     `Undefined` up to the index, then assigns the leaf at that index.
    ///   - Otherwise produces a dictionary with the string key.
    /// - Key dot mapping: when `options.getDecodeDotInKeys == true`, `"%2E"/"%2e"` inside key segments
    ///   map to literal "." (case‑insensitive).
    /// - Array normalization: arrays of optionals are normalized to arrays of `Any` by mapping `nil → NSNull`.
    ///
    /// - Parameters:
    ///   - chain: Segments returned by `splitKeyIntoSegments`.
    ///   - value: The RHS value for the leaf (already post-processed if `valuesParsed == true`).
    ///   - options: Active `DecodeOptions`.
    ///   - valuesParsed: If `true`, `value` has already gone through decoder/comma logic.
    /// - Returns: The nested fragment (array or dictionary) to be merged into the root.
    @usableFromInline
    internal static func parseObject(
        chain: [String],
        value: Any?,
        options: DecodeOptions,
        valuesParsed: Bool
    ) throws -> Any? {
        // Compute current list length if the last segment is "[]"
        let currentListLength: Int = {
            guard let last = chain.last, last == "[]" else { return 0 }
            // Try to interpret parent as an integer index (best-effort mirroring the Kotlin)
            let parentKey = chain.dropLast().joined()
            guard let idx = Int(parentKey) else { return 0 }
            if let outer = value as? [Any?], idx >= 0, idx < outer.count,
                let inner = outer[idx] as? [Any?]
            {
                return inner.count
            }
            return 0
        }()

        var leaf: Any? =
            valuesParsed
            ? value
            : try parseListValue(
                value,
                options: options,
                currentListLength: currentListLength,
                isFirstOccurrence: true
            )

        // Walk backwards from leaf to root
        for index in stride(from: chain.count - 1, through: 0, by: -1) {
            let root = chain[index]
            let obj: Any?

            if root == "[]" && options.parseLists {
                if Utils.isOverflow(leaf) {
                    obj = leaf
                } else if options.allowEmptyLists
                    && ((leaf as? String) == "" || (options.strictNullHandling && leaf == nil))
                {
                    obj = [Any]()  // empty list
                } else {
                    let valueForCombine: Any? = {
                        if let arr = leaf as? [Any] { return arr }
                        if let arrOpt = leaf as? [Any?] { return arrOpt }
                        return leaf ?? NSNull()
                    }()
                    obj = Utils.combine([], valueForCombine, listLimit: options.listLimit)
                }
            } else {
                var mutableObj: [AnyHashable: Any] = [:]

                // Strip surrounding brackets, e.g. "[0]" -> "0", "[]" -> ""
                let cleanRoot: String = {
                    if root.hasPrefix("["), root.hasSuffix("]"), root.count >= 2 {
                        let start = root.index(after: root.startIndex)
                        let end = root.index(before: root.endIndex)
                        return String(root[start..<end])
                    }
                    return root
                }()

                // Optionally decode "%2E" into "." for keys
                let decodedRoot: String =
                    options.getDecodeDotInKeys
                    ? cleanRoot.replacingOccurrences(
                        of: "%2E", with: ".", options: .caseInsensitive)
                    : cleanRoot

                // Parity: when list parsing is disabled or listLimit < 0,
                // treat "[]" as a dictionary key "0".
                if (!options.parseLists || options.listLimit < 0) && decodedRoot.isEmpty {
                    // Treat "[]" as dictionary key "0"
                    mutableObj["0"] = (leaf ?? NSNull())
                    obj = mutableObj
                } else if let idx = Int(decodedRoot),
                    idx >= 0,
                    root != decodedRoot,  // must have been "[0]"
                    String(idx) == decodedRoot,
                    options.parseLists,
                    idx <= options.listLimit
                {
                    // valid bracketed numeric index ⇒ array shell
                    var list = Array(repeating: Undefined.instance as Any, count: idx + 1)
                    list[idx] = (leaf ?? NSNull())
                    obj = list
                } else {
                    // default: dictionary with *string* key
                    mutableObj[decodedRoot] = (leaf ?? NSNull())
                    obj = mutableObj
                }
            }

            leaf = obj
        }

        return leaf
    }
}

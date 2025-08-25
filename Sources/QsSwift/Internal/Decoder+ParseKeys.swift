import Foundation
import OrderedCollections

extension QsSwift.Decoder {
    /// Splits a single key into segments (respecting dot-notation and depth rules),
    /// then builds the nested structure for that key and assigns `value` at the leaf.
    ///
    /// Example:
    ///   givenKey: "a[b][0][]"            → segments: ["a", "[b]", "[0]", "[]"]
    ///   givenKey: "a.b.c" (allowDots)    → segments: ["a", "[b]", "[c]"]
    ///   → `parseObject(...)` turns segments into the nested fragment and assigns the leaf.
    ///
    /// - Parameters:
    ///   - givenKey: The raw key (may include brackets and/or dots).
    ///   - value: The decoded RHS value to insert.
    ///   - options: Active `DecodeOptions`.
    ///   - valuesParsed: `true` if `value` already reflects comma splitting, decoder, etc.
    /// - Returns: A nested map/array fragment suitable for merging into the root object.
    /// - Throws: `.depthExceeded` (if `strictDepth == true` and `depth` is exceeded).
    @usableFromInline
    internal static func parseKeys(
        givenKey: String?,
        value: Any?,
        options: DecodeOptions,
        valuesParsed: Bool
    ) throws -> Any? {
        guard let givenKey, !givenKey.isEmpty else { return nil }

        let segments = try splitKeyIntoSegments(
            originalKey: givenKey,
            allowDots: options.getAllowDots,
            maxDepth: options.depth,
            strictDepth: options.strictDepth
        )

        return try parseObject(
            chain: segments,
            value: value,
            options: options,
            valuesParsed: valuesParsed
        )
    }

    /// Converts a key into bracket segments, enforcing depth and dot‑notation rules.
    ///
    /// Steps:
    /// 1. If `allowDots == true`, rewrite top‑level `.segment` into `[segment]` (dots inside brackets are ignored).
    /// 2. If `maxDepth == 0`, never split (return the whole key as a single segment).
    /// 3. Otherwise, extract up to `maxDepth` **balanced** bracket groups (including the brackets).
    /// 4. If there is a remainder:
    ///     • when `strictDepth == true` **and** all processed groups were well‑formed, throw `.depthExceeded`.
    ///     • otherwise (depth overflow **or** unterminated bracket group), stash the raw remainder
    ///       starting at the next unprocessed `'['` as a **single synthetic segment** by wrapping it:
    ///       `"[" + remainder + "]"`.
    ///
    /// Examples:
    ///   "a[b][c]"                   → ["a", "[b]", "[c]"]
    ///   "a.b.c" (allowDots)        → ["a", "[b]", "[c]"]
    ///   "a.b.c" (allowDots, depth=1, strictDepth=false) → ["a", "[b]", "[[c]]"]
    ///   "a[b][c][d]" (depth=2, strictDepth=false)      → ["a", "[b]", "[c]", "[[d]]"]
    ///   "a[b[c" (unterminated)                            → ["a", "[[b[c]"]
    ///
    /// - Parameters:
    ///   - originalKey: The input key string.
    ///   - allowDots: Whether `.` should be treated as `[segment]` at top level.
    ///   - maxDepth: Maximum number of bracket segments to extract.
    ///   - strictDepth: Throw instead of collapsing remainder when over limit and well‑formed.
    /// - Returns: An array of segments to drive `parseObject`.
    /// - Throws: `.depthExceeded` when `strictDepth == true` and the overflow is well‑formed.
    @usableFromInline
    internal static func splitKeyIntoSegments(
        originalKey: String,
        allowDots: Bool,
        maxDepth: Int,
        strictDepth: Bool
    ) throws -> [String] {
        // Depth 0 semantics: never split, never transform (qs/Kotlin parity).
        if maxDepth <= 0 {
            return [originalKey]
        }

        // Apply top-level dot→bracket only when allowDots is enabled.
        let key: String = allowDots ? dotToBracket(originalKey) : originalKey

        // Prepare result; reserve based on '[' count.
        var segments: [String] = []
        segments.reserveCapacity(key.filter { $0 == "[" }.count + 1)

        // Work with a character array for index arithmetic.
        let chars = Array(key)
        let length = chars.count

        // Find the first '[' to separate the non-bracket parent prefix.
        var firstOpen = -1
        var idx = 0
        while idx < length, chars[idx] != "[" { idx += 1 }
        firstOpen = (idx < length) ? idx : -1

        // Append the parent prefix (if any).
        if firstOpen > 0 {
            segments.append(String(chars[0..<firstOpen]))
        } else if firstOpen == -1 {
            // No brackets at all → the whole key is a single literal segment.
            return [key]
        }

        // Walk bracket groups, collecting up to maxDepth balanced segments.
        var open = firstOpen
        var collected = 0
        var unterminated = false

        while open >= 0, collected < maxDepth {
            var i2 = open + 1
            var level = 1
            var close = -1

            // Balance nested '[' and ']' *within the same group* so "[with[inner]]" stays one segment.
            while i2 < length {
                if chars[i2] == "[" {
                    level += 1
                } else if chars[i2] == "]" {
                    level -= 1
                    if level == 0 {
                        close = i2
                        break
                    }
                }
                i2 += 1
            }

            if close < 0 {
                // Unterminated bracket group: stop collecting; stash from `open` as opaque remainder.
                unterminated = true
                break
            }

            // Include the surrounding brackets for this balanced group.
            segments.append(String(chars[open...close]))
            collected += 1

            // Advance to the next '[' after this closed group.
            var nextOpen = close + 1
            while nextOpen < length, chars[nextOpen] != "[" { nextOpen += 1 }
            open = (nextOpen < length) ? nextOpen : -1
        }

        // Handle remainder (either depth overflow or unterminated group).
        if open >= 0 {
            if strictDepth && !unterminated {
                throw DecodeError.depthExceeded(maxDepth: maxDepth)
            }
            // Kotlin parity: wrap the raw remainder (from the next unprocessed '[') in one synthetic segment.
            segments.append("[" + String(chars[open..<length]) + "]")
        }

        return segments
    }

    // MARK: - Dot → Bracket converter (when allowDots = true)

    /// Rewrites `.segment` into `[segment]` when dot‑notation is enabled.
    ///
    /// Depth‑aware: only splits dots at **top level** (depth == 0); dots inside brackets
    /// are preserved. Skips pathological `..` and `.[` cases:
    /// - leading "." is preserved (e.g. ".a" → ".a")
    /// - the first dot in "a..b" is preserved (→ "a.[b]")
    /// - ".[" is treated as if the dot wasn’t there (→ "a[b]")
    ///
    /// This is the active implementation used by `splitKeyIntoSegments` (the old regex‑based
    /// approach is retained above only for historical reference).
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    private static func dotToBracket(_ input: String) -> String {
        // Depth-aware scanner that only splits dots at top level.
        if !input.contains(".") { return input }

        var out = String()
        out.reserveCapacity(input.count)
        let chars = Array(input)
        let length = chars.count
        var index = 0
        var depth = 0

        while index < length {
            let ch = chars[index]
            switch ch {
            case "[":
                depth += 1
                out.append(ch)
                index += 1

            case "]":
                if depth > 0 { depth -= 1 }
                out.append(ch)
                index += 1

            case ".":
                if depth == 0 {
                    let hasNext = (index + 1) < length
                    let next = hasNext ? chars[index + 1] : "\u{0}"

                    if next == "[" {
                        // Skip the dot so "a.[b]" behaves like "a[b]"
                        index += 1
                    } else if !hasNext || next == "." {
                        // Trailing dot, or first dot in "a..b": keep literal "."
                        out.append(".")
                        index += 1
                    } else {
                        // Normal split: ".segment" → "[segment]"
                        var segmentEnd = index + 1
                        while segmentEnd < length && chars[segmentEnd] != "." && chars[segmentEnd] != "[" {
                            segmentEnd += 1
                        }
                        out.append("[")
                        out.append(String(chars[(index + 1)..<segmentEnd]))
                        out.append("]")
                        index = segmentEnd
                    }
                } else {
                    out.append(".")
                    index += 1
                }

            case "%":
                // Preserve percent sequences verbatim; we never split on %2E here.
                out.append("%")
                index += 1

            default:
                out.append(ch)
                index += 1
            }
        }

        return out
    }
}

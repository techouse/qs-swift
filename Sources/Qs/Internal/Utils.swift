import DequeModule
import Foundation
import OrderedCollections

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A collection of utility methods used by the library.
internal enum Utils {
    // MARK: - Constants

    /// The maximum length of a segment to encode in a single pass.
    private static let segmentLimit = 1024

    // MARK: - Merge

    /// Merges two objects, where the source object overrides the target object.
    /// If the source is a Dictionary, it will merge its entries into the target.
    /// If the source is an Array, it will append its items to the target.
    /// If the source is a primitive, it will replace the target.
    ///
    /// - Parameters:
    ///   - target: The target object to merge into.
    ///   - source: The source object to merge from.
    ///   - options: Optional decode options for merging behavior.
    /// - Returns: The merged object.
    static func merge(target: Any?, source: Any?, options: DecodeOptions = DecodeOptions()) -> Any?
    {
        guard let source = source else { return target }

        if let tArr = target as? [Any?], let sDict = source as? [AnyHashable: Any] {
            var tDict: [AnyHashable: Any] = [:]
            for (i, v) in tArr.enumerated() where !(v is Undefined) {
                tDict[i] = v ?? NSNull()
            }
            for (k, v) in sDict { tDict[k] = v }
            return tDict
        }

        if let tDict = target as? [AnyHashable: Any], let sArr = source as? [Any?] {
            var sDict: [AnyHashable: Any] = [:]
            for (i, v) in sArr.enumerated() where !(v is Undefined) {
                sDict[i] = v ?? NSNull()
            }
            return merge(target: tDict, source: sDict, options: options)
        }

        if !(source is [AnyHashable: Any]) {
            if var targetOSet = target as? OrderedSet<AnyHashable> {
                if let sourceOSet = source as? OrderedSet<AnyHashable> {
                    targetOSet.formUnion(sourceOSet)  // keeps first-seen order
                    return targetOSet
                } else if let seq = asSequence(source) {
                    for el in seq where !(el is Undefined) {
                        if let h = el as? AnyHashable { _ = targetOSet.updateOrAppend(h) }
                    }
                    return targetOSet
                } else if source is Undefined {
                    return targetOSet
                } else if let h = source as? AnyHashable {
                    _ = targetOSet.updateOrAppend(h)
                    return targetOSet
                }
            }

            if var targetSet = target as? Set<AnyHashable> {
                if let sourceSet = source as? Set<AnyHashable> {
                    return targetSet.union(sourceSet)
                } else if let seq = asSequence(source) {
                    let items =
                        seq
                        .filter { !($0 is Undefined) }
                        .compactMap { $0 as? AnyHashable }
                    return targetSet.union(items)
                } else if source is Undefined {
                    return targetSet
                } else {
                    if let h = source as? AnyHashable { targetSet.insert(h) }
                    return targetSet
                }
            }

            if let targetArray = target as? [Any] {
                if targetArray.contains(where: { $0 is Undefined }) {
                    var mutableTarget: [Int: Any?] = [:]

                    for (index, value) in targetArray.enumerated() {
                        mutableTarget[index] = value
                    }

                    if let seq = asSequence(source) {
                        for (index, item) in seq.enumerated() where !(item is Undefined) {
                            mutableTarget[index] = item
                        }
                    } else {
                        mutableTarget[mutableTarget.count] = source
                    }

                    if !options.parseLists
                        && mutableTarget.values.contains(where: { $0 is Undefined })
                    {
                        return mutableTarget.values.compactMap { $0 is Undefined ? nil : $0 }
                    }

                    if target is Set<AnyHashable> {
                        return Set(mutableTarget.values.compactMap { $0 as? AnyHashable })
                    }

                    return mutableTarget.sorted { $0.key < $1.key }.map(\.value)
                } else {
                    if let seq = asSequence(source) {
                        let targetMaps = targetArray.allSatisfy {
                            $0 is [AnyHashable: Any] || $0 is Undefined
                        }
                        let sourceMaps = seq.allSatisfy {
                            $0 is [AnyHashable: Any] || $0 is Undefined
                        }

                        if targetMaps && sourceMaps {
                            var mutableTarget: [Int: Any?] = [:]

                            for (index, value) in targetArray.enumerated() {
                                mutableTarget[index] = value
                            }

                            for (index, item) in seq.enumerated() {
                                if let existing = mutableTarget[index] {
                                    mutableTarget[index] = merge(
                                        target: existing!, source: item, options: options)
                                } else {
                                    mutableTarget[index] = item
                                }
                            }

                            return mutableTarget.sorted { $0.key < $1.key }.map(\.value)
                        } else {
                            let filtered = seq.filter { !($0 is Undefined) }
                            return targetArray + filtered
                        }
                    } else {
                        if var targetOSet = target as? OrderedSet<AnyHashable>,
                            let h = source as? AnyHashable
                        {
                            _ = targetOSet.updateOrAppend(h)
                            return targetOSet
                        }
                        if let targetSet = target as? Set<AnyHashable>,
                            let h = source as? AnyHashable
                        {
                            return targetSet.union([h])
                        }
                        return targetArray + [source]
                    }
                }
            } else if let targetDict = target as? [AnyHashable: Any] {
                var mutableTarget = targetDict

                if let seq = asSequence(source) {
                    for (index, item) in seq.enumerated() where !(item is Undefined) {
                        mutableTarget[index] = item
                    }
                } else if !(source is Undefined) {
                    let key = String(describing: source)
                    if !key.isEmpty { mutableTarget[key] = true }
                }

                return mutableTarget
            } else {
                if let seq = asSequence(source) {
                    let filtered = seq.filter { !($0 is Undefined) }
                    var result: [Any?] = [target]  // preserve nil at index 0
                    result.append(contentsOf: filtered)
                    return result
                }
                return [target as Any?, source as Any?]
            }
        }

        if target == nil || !(target is [AnyHashable: Any]) {
            if let targetArray = target as? [Any] {
                var mutableTarget: [AnyHashable: Any] = [:]
                for (index, value) in targetArray.enumerated() {
                    if !(value is Undefined) {
                        mutableTarget[index] = value
                    }
                }

                if let sourceDict = source as? [AnyHashable: Any] {
                    for (key, value) in sourceDict {
                        mutableTarget[key] = value
                    }
                }
                return mutableTarget
            } else {
                var mutableTarget: [Any] = []
                if let target = target {
                    mutableTarget.append(target)
                }

                if let sourceArray = source as? [Any] {
                    mutableTarget.append(contentsOf: sourceArray.filter { !($0 is Undefined) })
                } else {
                    mutableTarget.append(source)
                }

                return mutableTarget
            }
        }

        var mergeTarget: [AnyHashable: Any]

        if let targetArray = target as? [Any], asSequence(source) == nil {
            mergeTarget = [:]
            for (index, value) in targetArray.enumerated() {
                if !(value is Undefined) {
                    mergeTarget[index] = value
                }
            }
        } else {
            mergeTarget = target as! [AnyHashable: Any]
        }

        if let sourceDict = source as? [AnyHashable: Any] {
            for (key, value) in sourceDict {
                if let existingValue = mergeTarget[key] {
                    mergeTarget[key] = merge(target: existingValue, source: value, options: options)
                } else {
                    mergeTarget[key] = value
                }
            }
        }

        return mergeTarget
    }

    // MARK: - Escape

    /// A Swift representation of the deprecated JavaScript escape function
    /// https://developer.mozilla.org/en-US/docs/web/javascript/reference/global_objects/escape
    @available(*, deprecated, message: "Use addingPercentEncoding instead")
    static func escape(_ s: String, format: Format = .rfc3986) -> String {
        _escape(s, format: format)
    }

    private static func _escape(_ str: String, format: Format) -> String {
        let allowParens = (format == .rfc1738)

        // Fast path: all ASCII + safe set ⇒ return as-is
        var needsEscaping = false
        for s in str.unicodeScalars {
            let v = s.value
            if v < 128 {
                if !isEscapeSafe(UInt8(v), allowParens: allowParens) {
                    needsEscaping = true
                    break
                }
            } else {
                needsEscaping = true
                break
            }
        }
        if !needsEscaping { return str }

        var out = String()
        // Heuristic: most chars become %XX (3 bytes). Your test becomes ~3x.
        out.reserveCapacity(str.unicodeScalars.count * 3)

        for s in str.unicodeScalars {
            let v = s.value
            if v < 128 {
                let b = UInt8(v)
                if isEscapeSafe(b, allowParens: allowParens) {
                    out.unicodeScalars.append(s)
                    continue
                }
            }
            if v < 256 {
                out += hexTable[Int(v)]  // "%XX"
            } else if v <= 0xFFFF {
                out.append("%u")
                appendHex4(v, to: &out)  // "%uXXXX"
            } else {
                // surrogate pair as two %u sequences
                let adj = v - 0x10000
                let high = 0xD800 + (adj >> 10)
                let low = 0xDC00 + (adj & 0x3FF)
                out.append("%u")
                appendHex4(high, to: &out)
                out.append("%u")
                appendHex4(low, to: &out)
            }
        }
        return out
    }

    @inline(__always)
    private static func isEscapeSafe(_ b: UInt8, allowParens: Bool) -> Bool {
        switch b {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A,  // 0-9 A-Z a-z
            0x40, 0x2A, 0x5F, 0x2D, 0x2B, 0x2E, 0x2F:  // @ * _ - + . /
            return true
        case 0x28, 0x29:  // ( )
            return allowParens
        default:
            return false
        }
    }

    @inline(__always)
    private static func hexDigit(_ x: UInt32) -> UInt8 {
        let n = x & 0xF
        return n < 10 ? (UInt8(48) + UInt8(n)) : (UInt8(55) + UInt8(n))  // '0'..'9','A'..'F'
    }

    @inline(__always)
    private static func appendHex4(_ v: UInt32, to out: inout String) {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes[0] = hexDigit(v >> 12)
        bytes[1] = hexDigit(v >> 8)
        bytes[2] = hexDigit(v >> 4)
        bytes[3] = hexDigit(v)
        out += String(bytes: bytes, encoding: .ascii)!
    }

    // MARK: - Unescape

    /// A Swift representation of the deprecated JavaScript unescape function
    /// https://developer.mozilla.org/en-US/docs/web/javascript/reference/global_objects/unescape
    @available(*, deprecated, message: "Use removingPercentEncoding instead")
    static func unescape(_ s: String) -> String {
        _unescape(s)
    }

    private static func _unescape(_ s: String) -> String {
        let nib = makeNibbleTable()

        @inline(__always)
        func utf8Emit(_ cp: Int32, _ out: UnsafeMutablePointer<UInt8>, _ w: inout Int) {
            if cp < 0x80 {
                out[w] = UInt8(cp)
                w &+= 1
            } else if cp < 0x800 {
                out[w] = 0xC0 | UInt8(cp >> 6)
                out[w &+ 1] = 0x80 | UInt8(cp & 0x3F)
                w &+= 2
            } else if cp < 0x10000 {
                out[w] = 0xE0 | UInt8(cp >> 12)
                out[w &+ 1] = 0x80 | UInt8((cp >> 6) & 0x3F)
                out[w &+ 2] = 0x80 | UInt8(cp & 0x3F)
                w &+= 3
            } else {
                out[w] = 0xF0 | UInt8(cp >> 18)
                out[w &+ 1] = 0x80 | UInt8((cp >> 12) & 0x3F)
                out[w &+ 2] = 0x80 | UInt8((cp >> 6) & 0x3F)
                out[w &+ 3] = 0x80 | UInt8(cp & 0x3F)
                w &+= 4
            }
        }

        func fast(_ src: UnsafeBufferPointer<UInt8>) -> String {
            let n = src.count
            if n == 0 { return "" }

            let outBytes: [UInt8] = .init(unsafeUninitializedCapacity: n) { outBuf, initialized in
                let p = src.baseAddress!
                let out = outBuf.baseAddress!
                var i = 0
                var w = 0

                while i < n {
                    // 1) copy straight run until next '%'
                    let runStart = i
                    while i < n, p[i] != 37 /* '%' */ { i &+= 1 }
                    if i > runStart {
                        out.advanced(by: w).update(
                            from: p.advanced(by: runStart), count: i - runStart)
                        w &+= (i - runStart)
                        if i == n { break }
                    }

                    // now p[i] == '%'
                    // Try %uXXXX
                    if i &+ 5 < n, (p[i &+ 1] | 0x20) == 117 {  // 'u'/'U'
                        let h1 = nib[Int(p[i &+ 2])]
                        let h2 = nib[Int(p[i &+ 3])]
                        let h3 = nib[Int(p[i &+ 4])]
                        let h4 = nib[Int(p[i &+ 5])]
                        if h1 >= 0, h2 >= 0, h3 >= 0, h4 >= 0 {
                            let cp =
                                ((Int32(h1) << 12) | (Int32(h2) << 8) | (Int32(h3) << 4) | Int32(h4))
                            utf8Emit(cp, out, &w)
                            i &+= 6
                            continue
                        }
                    }

                    // Try %XX
                    if i &+ 2 < n {
                        let h1 = nib[Int(p[i &+ 1])]
                        let h2 = nib[Int(p[i &+ 2])]
                        if h1 >= 0, h2 >= 0 {
                            let byte = Int32((h1 << 4) | h2)
                            // Interpret as U+00..FF
                            if byte < 0x80 {
                                out[w] = UInt8(byte)
                                w &+= 1
                            } else {
                                out[w] = 0xC0 | UInt8(byte >> 6)
                                out[w &+ 1] = 0x80 | UInt8(byte & 0x3F)
                                w &+= 2
                            }
                            i &+= 3
                            continue
                        }
                    }

                    // Fallback: literal '%'
                    out[w] = 37
                    w &+= 1
                    i &+= 1
                }

                initialized = w
            }

            return String(decoding: outBytes, as: UTF8.self)
        }

        if let s = s.utf8.withContiguousStorageIfAvailable({ fast($0) }) {
            return s
        } else {
            let tmp = Array(s.utf8)
            return tmp.withUnsafeBufferPointer { fast($0) }
        }
    }

    @inline(__always)
    private static func makeNibbleTable() -> [Int16] {
        var t = [Int16](repeating: -1, count: 256)
        for c in 48...57 { t[c] = Int16(c - 48) }  // '0'..'9'
        for c in 65...70 { t[c] = Int16(c - 55) }  // 'A'..'F'
        for c in 97...102 { t[c] = Int16(c - 87) }  // 'a'..'f'
        return t
    }

    // MARK: - Encode

    /// Encodes a value into a URL-encoded string.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - charset: The character set to use for encoding. Defaults to UTF-8.
    ///   - format: The encoding format to use. Defaults to RFC 3986.
    /// - Returns: The encoded string.
    static func encode(
        _ value: Any?,
        charset: String.Encoding = .utf8,
        format: Format = .rfc3986
    ) -> String {
        if value is [Any]
            || value is [AnyHashable: Any]
            || value is OrderedDictionary<String, Any>
            || value is OrderedDictionary<AnyHashable, Any>
            || value is Undefined
        {
            return ""
        }

        let str: String
        switch value {
        case let data as Data: str = String(data: data, encoding: charset) ?? ""
        case let s as String: str = s
        default: str = String(describing: value ?? "")
        }
        if str.isEmpty { return "" }

        if charset == .isoLatin1 {
            let escaped = _escape(str, format: format)
            do {
                let rx = try NSRegularExpression(pattern: #"%u([0-9A-Fa-f]{4})"#)
                let ns = escaped as NSString
                var out = ""
                var last = 0
                for m in rx.matches(in: escaped, range: NSRange(location: 0, length: ns.length)) {
                    let r = m.range
                    let hexR = m.range(at: 1)
                    out += ns.substring(with: NSRange(location: last, length: r.location - last))
                    let hex = ns.substring(with: hexR)
                    if let v = Int(hex, radix: 16) {
                        out += "%26%23\(v)%3B"
                    } else {
                        out += ns.substring(with: r)
                    }
                    last = r.location + r.length
                }
                out += ns.substring(from: last)
                return out
            } catch { return escaped }
        }

        // Fast path: if no byte needs encoding, return the original
        let allowParens = (format == .rfc1738)
        var needsEncoding = false
        for b in str.utf8 {
            if !(isUnreserved(b) || (allowParens && (b == 0x28 || b == 0x29))) {
                needsEncoding = true
                break
            }
        }
        if !needsEncoding { return str }

        // Encode in one pass over UTF-8 bytes
        var out = String()
        out.reserveCapacity(str.utf8.count)  // good heuristic

        for b in str.utf8 {
            if isUnreserved(b) || (allowParens && (b == 0x28 || b == 0x29)) {
                out.append(Character(UnicodeScalar(b)))
            } else {
                out += hexTable[Int(b)]  // your precomputed "%XX"
            }
        }

        return format.formatter.apply(out)
    }

    @inline(__always)
    private static func isUnreserved(_ b: UInt8) -> Bool {
        switch b {
        case 0x2D, 0x2E, 0x5F, 0x7E, 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    // MARK: - Decode

    /// Decodes a URL-encoded string into its original form.
    ///
    /// - Parameters:
    ///   - str: The URL-encoded string to decode.
    ///   - charset: The character set to use for decoding. Defaults to UTF-8.
    /// - Returns: The decoded string, or nil if the input is nil.
    static func decode(_ str: String?, charset: String.Encoding = .utf8) -> String? {
        guard let str = str else { return nil }

        let strWithoutPlus = str.replacingOccurrences(of: "+", with: " ")

        if charset == .isoLatin1 {
            do {
                let pattern = #"%[0-9a-f]{2}"#
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let range = NSRange(location: 0, length: strWithoutPlus.count)

                let result = NSMutableString(string: strWithoutPlus)
                let matches = regex.matches(in: strWithoutPlus, options: [], range: range)

                // Process matches in reverse order to avoid index shifting
                for match in matches.reversed() {
                    let matchRange = match.range
                    if let swiftRange = Range(matchRange, in: strWithoutPlus) {
                        let matchedString = String(strWithoutPlus[swiftRange])
                        let unescaped = _unescape(matchedString)
                        result.replaceCharacters(in: matchRange, with: unescaped)
                    }
                }

                return String(result)
            } catch {
                return strWithoutPlus
            }
        }

        return strWithoutPlus.removingPercentEncoding
    }

    // MARK: - Compact

    // Replace your existing `compact` with this:

    /// Compact a nested structure by removing all `Undefined` values.
    /// - Note: `NSNull()` is preserved (represents an explicit `null`).
    /// - If `allowSparseLists` is `false` (default), array holes are *removed* (indexes shift).
    /// - If `allowSparseLists` is `true`, holes are kept as `NSNull()` (Swift arrays can't be truly sparse).
    static func compact(
        _ root: inout [String: Any?],
        allowSparseLists: Bool = false
    ) -> [String: Any?] {
        @inline(__always)
        func compactValue(_ v: Any?, allowSparse: Bool) -> Any? {
            // Drop Undefined entirely
            if v is Undefined { return nil }

            // Dictionary branch
            if let dict = v as? [String: Any?] {
                var out: [String: Any?] = [:]
                out.reserveCapacity(dict.count)
                for (k, val) in dict {
                    if let cv = compactValue(val, allowSparse: allowSparse) {
                        out[k] = cv
                    }
                    // else: value was Undefined → remove the key
                }
                return out
            }

            // Array branches – tolerate both [Any] and [Any?] shapes.
            if let arr = v as? [Any] {
                var out: [Any] = []
                out.reserveCapacity(arr.count)
                for e in arr {
                    if e is Undefined {
                        if allowSparse { out.append(NSNull()) }
                        // else: drop it
                        continue
                    }
                    if let subDict = e as? [String: Any?] {
                        if let cv = compactValue(subDict, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArr = e as? [Any] {
                        if let cv = compactValue(subArr, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArrOpt = e as? [Any?] {
                        if let cv = compactValue(subArrOpt, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else {
                        out.append(e)
                    }
                }
                return out
            }

            if let arrOpt = v as? [Any?] {
                var out: [Any] = []
                out.reserveCapacity(arrOpt.count)
                for e in arrOpt {
                    guard let e = e else {
                        out.append(NSNull())
                        continue
                    }
                    if e is Undefined {
                        if allowSparse { out.append(NSNull()) }
                        continue
                    }
                    if let subDict = e as? [String: Any?] {
                        if let cv = compactValue(subDict, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArr = e as? [Any] {
                        if let cv = compactValue(subArr, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else if let subArrOpt2 = e as? [Any?] {
                        if let cv = compactValue(subArrOpt2, allowSparse: allowSparse) {
                            out.append(cv)
                        }
                    } else {
                        out.append(e)
                    }
                }
                return out
            }

            // Primitive (String/Number/Bool/Date/URL/NSNull/etc)
            return v
        }

        var newRoot: [String: Any?] = [:]
        newRoot.reserveCapacity(root.count)
        for (k, v) in root {
            if let cv = compactValue(v, allowSparse: allowSparseLists) {
                newRoot[k] = cv
            }
        }
        root = newRoot
        return root
    }

    /// Remove `Undefined`, coerce optionals to concrete `Any`, keep `NSNull`,
    /// and (optionally) preserve sparse arrays with `NSNull()` placeholders.
    static func compactToAny(
        _ root: [String: Any?],
        allowSparseLists: Bool
    ) -> [String: Any] {
        func normalizeArray(_ arr: [Any?]) -> [Any] {
            var out: [Any] = []
            out.reserveCapacity(arr.count)

            for el in arr {
                switch el {
                case is Undefined:
                    if allowSparseLists { out.append(NSNull()) }
                // else: drop it
                case let d as [String: Any?]:
                    out.append(compactToAny(d, allowSparseLists: allowSparseLists))
                case let a as [Any?]:
                    out.append(normalizeArray(a))
                case .some(let v):
                    out.append(v)
                case .none:
                    // explicit nil → NSNull so we can keep `[Any]`
                    out.append(NSNull())
                }
            }
            return out
        }

        var out: [String: Any] = [:]
        out.reserveCapacity(root.count)

        for (k, v) in root {
            switch v {
            case is Undefined:
                // drop
                continue
            case let d as [String: Any?]:
                out[k] = compactToAny(d, allowSparseLists: allowSparseLists)
            case let a as [Any?]:
                out[k] = normalizeArray(a)
            case .some(let vv):
                out[k] = vv
            case .none:
                out[k] = NSNull()
            }
        }
        return out
    }

    // MARK: - Combine

    /// Combines two objects into an array. If either object is an Array, its elements are added to the array.
    /// If either object is a primitive, it is added as a single element.
    ///
    /// - Parameters:
    ///   - a: The first object to combine.
    ///   - b: The second object to combine.
    /// - Returns: An array containing the combined elements.
    static func combine<T>(_ a: Any?, _ b: Any?) -> [T] {
        var result: [T] = []

        if let arrayA = a as? [T] {
            result.append(contentsOf: arrayA)
        } else if let itemA = a as? T {
            result.append(itemA)
        }

        if let arrayB = b as? [T] {
            result.append(contentsOf: arrayB)
        } else if let itemB = b as? T {
            result.append(itemB)
        }

        return result
    }

    // MARK: - Apply

    /// Applies a function to a value or each element in an Array. If the value is an Array,
    /// the function is applied to each element. If the value is a single item, the function is applied directly.
    ///
    /// - Parameters:
    ///   - value: The value or Array to apply the function to.
    ///   - fn: The function to apply.
    /// - Returns: The result of applying the function, or nil if the input is nil.
    static func apply<T>(_ value: Any?, _ fn: (T) -> T) -> Any? {
        if let array = value as? [T] {
            return array.map(fn)
        } else if let item = value as? T {
            return fn(item)
        }
        return nil
    }

    // MARK: - Non-nullish Primitive Check

    /// Checks if a value is a non-nullish primitive type. A non-nullish primitive is defined as a
    /// String, Number, Bool, enum, Date, or URL. If `skipNulls` is true, empty Strings and URLs are also considered non-nullish.
    ///
    /// - Parameters:
    ///   - value: The value to check.
    ///   - skipNulls: If true, empty Strings and URLs are not considered non-nullish.
    /// - Returns: True if the value is a non-nullish primitive, false otherwise.
    static func isNonNullishPrimitive(_ value: Any?, skipNulls: Bool = false) -> Bool {
        switch value {
        case let string as String:
            return skipNulls ? !string.isEmpty : true
        case is NSNumber, is Bool, is Date:
            return true
        case let url as URL:
            return skipNulls ? !url.absoluteString.isEmpty : true
        case is [Any],
            is [AnyHashable: Any],
            is OrderedDictionary<String, Any>,
            is OrderedDictionary<AnyHashable, Any>,
            is Undefined:
            return false
        case nil:
            return false
        default:
            return true
        }
    }

    // MARK: - Is Empty Check

    /// Checks if a value is empty. A value is considered empty if it is nil, Undefined, an empty
    /// String, an empty Array, or an empty Dictionary.
    ///
    /// - Parameter value: The value to check.
    /// - Returns: True if the value is empty, false otherwise.
    static func isEmpty(_ value: Any?) -> Bool {
        switch value {
        case nil, is Undefined:
            return true
        case let string as String:
            return string.isEmpty
        case let array as [Any]:
            return array.isEmpty
        case let od as OrderedDictionary<String, Any>:
            return od.isEmpty
        case let od as OrderedDictionary<AnyHashable, Any>:
            return od.isEmpty
        case let dict as [AnyHashable: Any]:
            return dict.isEmpty
        default:
            return false
        }
    }

    // MARK: - Interpret Numeric Entities

    /// Interpret numeric entities in a string, converting them to their Unicode characters.
    /// This function supports both decimal and hexadecimal numeric entities.
    ///
    /// - Parameter str: The input string potentially containing numeric entities.
    /// - Returns: A new string with numeric entities replaced by their corresponding characters.
    static func interpretNumericEntities(_ str: String) -> String {
        if str.count < 4 { return str }
        guard str.contains("&#") else { return str }

        var result = ""
        result.reserveCapacity(str.count)

        let end = str.endIndex
        var i = str.startIndex

        while i < end {
            let ch = str[i]
            if ch == "&" {
                let hashIdx = str.index(after: i)
                if hashIdx < end, str[hashIdx] == "#" {
                    var j = str.index(after: hashIdx)  // after '#'
                    var code = 0
                    let startDigits = j
                    while j < end, let d = str[j].wholeNumberValue {
                        code = code &* 10 &+ d
                        j = str.index(after: j)
                    }
                    if j < end, str[j] == ";", j > startDigits {
                        // Try surrogate pair
                        if (0xD800...0xDBFF).contains(code) {
                            let afterSemi = str.index(after: j)
                            if afterSemi < end, str[afterSemi] == "&" {
                                let hash2 = str.index(after: afterSemi)
                                if hash2 < end, str[hash2] == "#" {
                                    var k = str.index(after: hash2)
                                    var low = 0
                                    let startDigits2 = k
                                    while k < end, let d2 = str[k].wholeNumberValue {
                                        low = low &* 10 &+ d2
                                        k = str.index(after: k)
                                    }
                                    if k < end, str[k] == ";", k > startDigits2,
                                        (0xDC00...0xDFFF).contains(low)
                                    {
                                        let cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                                        if let scalar = UnicodeScalar(cp) {
                                            result.append(Character(scalar))
                                            i = str.index(after: k)  // consume both
                                            continue
                                        }
                                    }
                                }
                            }
                        }
                        // Single entity
                        if let scalar = UnicodeScalar(code) {
                            result.append(Character(scalar))
                            i = str.index(after: j)
                            continue
                        } else {
                            // Out-of-range or isolated surrogate → keep literal
                            result += String(str[i...j])
                            i = str.index(after: j)
                            continue
                        }
                    }
                }
            }
            result.append(ch)
            i = str.index(after: i)
        }
        return result
    }

    // MARK: - Deep bridge to Any WITHOUT recursion

    @inline(never)
    internal static func deepBridgeToAnyIterative(_ root: Any?) -> Any {
        final class DictBox { var dict: [String: Any] = [:] }
        final class ArrayBox {
            var arr: [Any]
            init(_ count: Int) { self.arr = Array(repeating: NSNull(), count: count) }
        }

        typealias Assign = (Any) -> Void
        enum Task {
            case build(node: Any?, assign: Assign)
            case commitDict(DictBox, Assign)
            case commitArray(ArrayBox, Assign)
        }

        var result: Any = NSNull()
        var stack: [Task] = [.build(node: root, assign: { result = $0 })]

        while let task = stack.popLast() {
            switch task {
            case let .build(node, assign):
                guard let node else {
                    assign(NSNull())
                    continue
                }

                if let dict = node as? [String: Any?] {
                    let box = DictBox()
                    stack.append(.commitDict(box, assign))
                    for (k, child) in dict {
                        stack.append(.build(node: child, assign: { v in box.dict[k] = v }))
                    }
                    continue
                }

                if let dictAHOpt = node as? [AnyHashable: Any?] {
                    let box = DictBox()
                    stack.append(.commitDict(box, assign))
                    for (k, child) in dictAHOpt {
                        let ks = String(describing: k)
                        stack.append(.build(node: child, assign: { v in box.dict[ks] = v }))
                    }
                    continue
                }

                if let dictAH = node as? [AnyHashable: Any] {
                    let box = DictBox()
                    stack.append(.commitDict(box, assign))
                    for (k, child) in dictAH {
                        let ks = String(describing: k)
                        stack.append(.build(node: child, assign: { v in box.dict[ks] = v }))
                    }
                    continue
                }

                if let arr = node as? [Any] {
                    let box = ArrayBox(arr.count)
                    stack.append(.commitArray(box, assign))
                    for (i, child) in arr.enumerated() {
                        stack.append(.build(node: child, assign: { v in box.arr[i] = v }))
                    }
                    continue
                }

                if let arrOpt = node as? [Any?] {
                    let box = ArrayBox(arrOpt.count)
                    stack.append(.commitArray(box, assign))
                    for (i, child) in arrOpt.enumerated() {
                        stack.append(.build(node: child, assign: { v in box.arr[i] = v }))
                    }
                    continue
                }

                assign(node)

            case let .commitDict(box, assign):
                assign(box.dict)

            case let .commitArray(box, assign):
                assign(box.arr)
            }
        }

        return result
    }

    // --- Compact only when necessary (avoid deep recursion if no Undefined) ---
    #if QSBENCH_INLINE
        @inline(__always)
    #endif
    internal static func containsUndefined(_ root: Any?) -> Bool {
        var stack: [Any?] = [root]
        while let node = stack.popLast() {
            if node is Undefined { return true }

            if let d = node as? [String: Any?] {
                stack.append(contentsOf: d.values)  // values are Any?
            } else if let d = node as? [AnyHashable: Any] {
                stack.append(contentsOf: d.values.map { Optional($0) })  // wrap Any → Any?
            } else if let a = node as? [Any?] {
                stack.append(contentsOf: a)  // already Any?
            } else if let a = node as? [Any] {
                stack.append(contentsOf: a.map { Optional($0) })  // wrap Any → Any?
            }
        }
        return false
    }

    // MARK: - Sequence Helpers

    /// Converts a value to a sequence (array) if it is an array, ordered set, or set.
    private static func asSequence(_ v: Any) -> [Any]? {
        if let a = v as? [Any] { return a }
        if let os = v as? OrderedSet<AnyHashable> { return Array(os) }
        if let s = v as? Set<AnyHashable> { return Array(s) }
        return nil
    }

    // MARK: - Main-thread teardown & depth heuristics

    /// Very fast estimator for single-key-chain depth; caps work.
    @inline(__always)
    internal static func estimateSingleKeyChainDepth(_ v: Any?, cap: Int = 20_000) -> Int {
        var depth = 0
        var cur = v
        while depth < cap {
            if let d = cur as? [String: Any?], d.count == 1 {
                cur = d.first!.value
                depth += 1
                continue
            }
            if let d = cur as? [AnyHashable: Any?], d.count == 1 {
                cur = d.first!.value
                depth += 1
                continue
            }
            if let d = cur as? [AnyHashable: Any], d.count == 1 {
                cur = d.first!.value
                depth += 1
                continue
            }
            return depth
        }
        return depth
    }

    /// Decide if we should drop on main based on a quick scan of top-level values.
    /// This is cheap and catches the pathological "p→p→p..." shape.
    internal static func needsMainDrop(_ root: [String: Any?], threshold: Int) -> Bool {
        // fast exit for small graphs
        if threshold <= 0 { return false }
        for v in root.values {
            if estimateSingleKeyChainDepth(v, cap: threshold + 1) >= threshold {
                return true
            }
        }
        return false
    }

    /// Drop an object on the main thread, retaining it until the async block runs.
    /// This is useful for cleaning up resources that should be released on the main thread.
    @inline(__always)
    internal static func dropOnMainThread(_ obj: AnyObject?) {
        guard let obj else { return }
        let token = _RetainedToken(raw: Unmanaged.passRetained(obj))
        DispatchQueue.main.async { token.raw.release() }
    }

    // Keep the existing Any? convenience that forwards:
    @inline(__always)
    internal static func dropOnMainThread(_ payload: Any?) {
        dropOnMainThread(payload as AnyObject?)
    }
}

// A tiny wrapper so we can capture the retained token in a @Sendable closure.
private struct _RetainedToken: @unchecked Sendable {
    let raw: Unmanaged<AnyObject>
}

// A simple box to hold a payload for deferred execution on the main thread.
private final class _DropBox: @unchecked Sendable {
    var payload: Any?
    init(_ p: Any?) { payload = p }
    deinit { payload = nil }
}

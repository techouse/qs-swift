import Foundation

extension Utils {
    /// Interpret numeric entities in a string, converting them to their Unicode characters.
    /// Supports both **decimal** (e.g. `&#9731;`) and **hexadecimal** (e.g. `&#x2603;` / `&#X2603;`) forms.
    /// If a high-surrogate is immediately followed by a low-surrogate entity, they are combined
    /// into a single Unicode scalar.
    ///
    /// - Parameter str: The input string potentially containing numeric entities.
    /// - Returns: A new string with numeric entities replaced by their corresponding characters.
    @usableFromInline
    static func interpretNumericEntities(_ str: String) -> String {
        if str.count < 4 { return str }
        guard str.contains("&#") else { return str }

        // Local helper to decode a single hex digit
        @inline(__always)
        func hexVal(_ ch: Character) -> Int? {
            guard let scalarValue = ch.unicodeScalars.first?.value else { return nil }
            switch ch {
            case "0"..."9":
                return Int(scalarValue) - 48
            case "a"..."f":
                return 10 + Int(scalarValue) - 97
            case "A"..."F":
                return 10 + Int(scalarValue) - 65
            default:
                return nil
            }
        }

        var result = ""
        result.reserveCapacity(str.count)
        // swiftlint:disable identifier_name

        let end = str.endIndex
        var i = str.startIndex

        while i < end {
            let ch = str[i]
            if ch == "&" {
                let hashIdx = str.index(after: i)
                if hashIdx < end, str[hashIdx] == "#" {
                    var j = str.index(after: hashIdx)  // after '#'
                    var code = 0

                    // Detect hex form (optional 'x' or 'X') and parse digits accordingly
                    if j < end, str[j] == "x" || str[j] == "X" {
                        j = str.index(after: j)
                        let startDigits = j
                        while j < end, let hv = hexVal(str[j]) {
                            code = (code << 4) &+ hv
                            j = str.index(after: j)
                        }
                        if j < end, str[j] == ";", j > startDigits {
                            // Hex path complete; check surrogate-pair continuation
                            if (0xD800...0xDBFF).contains(code) {
                                let afterSemi = str.index(after: j)
                                if afterSemi < end, str[afterSemi] == "&" {
                                    let hash2 = str.index(after: afterSemi)
                                    if hash2 < end, str[hash2] == "#" {
                                        var k = str.index(after: hash2)
                                        var low = 0
                                        if k < end, str[k] == "x" || str[k] == "X" {
                                            k = str.index(after: k)
                                            let startDigits2 = k
                                            while k < end, let hv2 = hexVal(str[k]) {
                                                low = (low << 4) &+ hv2
                                                k = str.index(after: k)
                                            }
                                            if k < end, str[k] == ";", k > startDigits2,
                                                (0xDC00...0xDFFF).contains(low)
                                            {
                                                let cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                                                if let scalar = UnicodeScalar(cp) {
                                                    result.append(Character(scalar))
                                                    i = str.index(after: k)  // consume both entities
                                                    continue
                                                }
                                            }
                                        } else {
                                            // Decimal trailing entity after a hex high-surrogate
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
                                                    i = str.index(after: k)
                                                    continue
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            if let scalar = UnicodeScalar(code) {
                                result.append(Character(scalar))
                                i = str.index(after: j)
                                continue
                            } else {
                                // Out-of-range; keep literal
                                result += String(str[i...j])
                                i = str.index(after: j)
                                continue
                            }
                        }
                    } else {
                        // Decimal form
                        let startDigits = j
                        while j < end, let d = str[j].wholeNumberValue {
                            code = code &* 10 &+ d
                            j = str.index(after: j)
                        }
                        if j < end, str[j] == ";", j > startDigits {
                            // Try surrogate pair (both decimal or mixed with hex for the second half)
                            if (0xD800...0xDBFF).contains(code) {
                                let afterSemi = str.index(after: j)
                                if afterSemi < end, str[afterSemi] == "&" {
                                    let hash2 = str.index(after: afterSemi)
                                    if hash2 < end, str[hash2] == "#" {
                                        var k = str.index(after: hash2)
                                        var low = 0
                                        if k < end, str[k] == "x" || str[k] == "X" {
                                            // Hex low-surrogate following a decimal high-surrogate
                                            k = str.index(after: k)
                                            let startDigits2 = k
                                            while k < end, let hv2 = hexVal(str[k]) {
                                                low = (low << 4) &+ hv2
                                                k = str.index(after: k)
                                            }
                                            if k < end, str[k] == ";", k > startDigits2,
                                                (0xDC00...0xDFFF).contains(low)
                                            {
                                                let cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                                                if let scalar = UnicodeScalar(cp) {
                                                    result.append(Character(scalar))
                                                    i = str.index(after: k)
                                                    continue
                                                }
                                            }
                                        } else {
                                            // Decimal low-surrogate
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
                                                    i = str.index(after: k)
                                                    continue
                                                }
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
            }
            result.append(ch)
            i = str.index(after: i)
        }
        // swiftlint:enable identifier_name
        return result
    }
}

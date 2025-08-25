import Foundation

extension QsSwift.Utils {
    // MARK: - Decode

    /// Decodes a URL-encoded string into its original form.
    ///
    /// - Parameters:
    ///   - str: The URL-encoded string to decode.
    ///   - charset: The character set to use for decoding. Defaults to UTF-8.
    /// - Returns: The decoded string, or nil if the input is nil.
    @usableFromInline
    static func decode(_ str: String?, charset: String.Encoding = .utf8) -> String? {
        guard let str = str else { return nil }

        let strWithoutPlus = str.replacingOccurrences(of: "+", with: " ")

        if charset == .isoLatin1 {
            let regex = isoPercentByteRegex
            let range = NSRange(strWithoutPlus.startIndex..., in: strWithoutPlus)

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
        }

        return strWithoutPlus.removingPercentEncoding
    }

    // MARK: - Unescape

    /// A Swift representation of the deprecated JavaScript unescape function
    /// https://developer.mozilla.org/en-US/docs/web/javascript/reference/global_objects/unescape
    @available(*, deprecated, message: "Use removingPercentEncoding instead")
    @usableFromInline
    static func unescape(_ string: String) -> String {
        _unescape(string)
    }

    private static func _unescape(_ string: String) -> String {
        let nibble = makeNibbleTable()

        @inline(__always)
        func utf8Emit(_ codePoint: Int32, _ out: UnsafeMutablePointer<UInt8>, _ writeIndex: inout Int) {
            if codePoint < 0x80 {
                out[writeIndex] = UInt8(codePoint)
                writeIndex &+= 1
            } else if codePoint < 0x800 {
                out[writeIndex] = 0xC0 | UInt8(codePoint >> 6)
                out[writeIndex &+ 1] = 0x80 | UInt8(codePoint & 0x3F)
                writeIndex &+= 2
            } else if codePoint < 0x10000 {
                out[writeIndex] = 0xE0 | UInt8(codePoint >> 12)
                out[writeIndex &+ 1] = 0x80 | UInt8((codePoint >> 6) & 0x3F)
                out[writeIndex &+ 2] = 0x80 | UInt8(codePoint & 0x3F)
                writeIndex &+= 3
            } else {
                out[writeIndex] = 0xF0 | UInt8(codePoint >> 18)
                out[writeIndex &+ 1] = 0x80 | UInt8((codePoint >> 12) & 0x3F)
                out[writeIndex &+ 2] = 0x80 | UInt8((codePoint >> 6) & 0x3F)
                out[writeIndex &+ 3] = 0x80 | UInt8(codePoint & 0x3F)
                writeIndex &+= 4
            }
        }

        @inline(__always)
        func fast(_ src: UnsafeBufferPointer<UInt8>) -> String {
            let count = src.count
            if src.isEmpty { return "" }

            let outBytes: [UInt8] = .init(unsafeUninitializedCapacity: count) { outBuf, initialized in
                guard let srcBase = src.baseAddress else {
                    initialized = 0
                    return
                }
                guard let outBase = outBuf.baseAddress else {
                    initialized = 0
                    return
                }

                var index = 0
                var writeIndex = 0

                while index < count {
                    // 1) copy straight run until next '%'
                    let runStart = index
                    while index < count, srcBase[index] != 37 /* '%' */ { index &+= 1 }
                    if index > runStart {
                        outBase.advanced(by: writeIndex).update(
                            from: srcBase.advanced(by: runStart), count: index - runStart)
                        writeIndex &+= (index - runStart)
                        if index == count { break }
                    }

                    // now srcBase[index] == '%'
                    // Try %uXXXX
                    if index &+ 5 < count, (srcBase[index &+ 1] | 0x20) == 117 {  // 'u'/'U'
                        let h1 = nibble[Int(srcBase[index &+ 2])]
                        let h2 = nibble[Int(srcBase[index &+ 3])]
                        let h3 = nibble[Int(srcBase[index &+ 4])]
                        let h4 = nibble[Int(srcBase[index &+ 5])]
                        if h1 >= 0, h2 >= 0, h3 >= 0, h4 >= 0 {
                            let codePoint =
                                ((Int32(h1) << 12) | (Int32(h2) << 8) | (Int32(h3) << 4) | Int32(h4))
                            utf8Emit(codePoint, outBase, &writeIndex)
                            index &+= 6
                            continue
                        }
                    }

                    // Try %XX
                    if index &+ 2 < count {
                        let h1 = nibble[Int(srcBase[index &+ 1])]
                        let h2 = nibble[Int(srcBase[index &+ 2])]
                        if h1 >= 0, h2 >= 0 {
                            let byte = Int32((h1 << 4) | h2)
                            // Interpret as U+00..FF
                            if byte < 0x80 {
                                outBase[writeIndex] = UInt8(byte)
                                writeIndex &+= 1
                            } else {
                                outBase[writeIndex] = 0xC0 | UInt8(byte >> 6)
                                outBase[writeIndex &+ 1] = 0x80 | UInt8(byte & 0x3F)
                                writeIndex &+= 2
                            }
                            index &+= 3
                            continue
                        }
                    }

                    // Fallback: literal '%'
                    outBase[writeIndex] = 37
                    writeIndex &+= 1
                    index &+= 1
                }

                initialized = writeIndex
            }

            return String(bytes: outBytes, encoding: .utf8) ?? ""
        }

        if let result = string.utf8.withContiguousStorageIfAvailable({ fast($0) }) {
            return result
        } else {
            let tmp = Array(string.utf8)
            return tmp.withUnsafeBufferPointer { fast($0) }
        }
    }

    @inline(__always)
    private static func makeNibbleTable() -> [Int16] {
        var tbl = [Int16](repeating: -1, count: 256)
        for ch in 48...57 { tbl[ch] = Int16(ch - 48) }  // '0'..'9'
        for ch in 65...70 { tbl[ch] = Int16(ch - 55) }  // 'A'..'F'
        for ch in 97...102 { tbl[ch] = Int16(ch - 87) }  // 'a'..'f'
        return tbl
    }

    /// Precompiled regex for ISO-8859-1 percent bytes (%XX), case-insensitive.
    /// Cached once to avoid re-compiling on every decode call.
    private static let isoPercentByteRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"%[0-9a-f]{2}"#,
                options: .caseInsensitive
            )
        } catch {
            preconditionFailure("Invalid isoPercentByteRegex: \(error)")
        }
    }()
}

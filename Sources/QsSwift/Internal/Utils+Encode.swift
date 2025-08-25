import Foundation
import OrderedCollections

extension QsSwift.Utils {
    // MARK: - Encode

    /// Encodes a value into a URL-encoded string.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - charset: The character set to use for encoding. Defaults to UTF-8.
    ///   - format: The encoding format to use. Defaults to RFC 3986.
    /// - Returns: The encoded string.
    @usableFromInline
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
        case let stringValue as String: str = stringValue
        default: str = String(describing: value ?? "")
        }
        if str.isEmpty { return "" }

        if charset == .isoLatin1 {
            let escaped = _escape(str, format: format)
            let ns = escaped as NSString
            var out = ""
            var last = 0
            for match in uEscapeRegex.matches(in: escaped, range: NSRange(location: 0, length: ns.length)) {
                let range = match.range
                let hexRange = match.range(at: 1)
                out += ns.substring(with: NSRange(location: last, length: range.location - last))
                let hex = ns.substring(with: hexRange)
                if let codepoint = Int(hex, radix: 16) {
                    out += "%26%23\(codepoint)%3B"
                } else {
                    out += ns.substring(with: range)
                }
                last = range.location + range.length
            }
            out += ns.substring(from: last)
            return out
        }

        // Fast path: if no byte needs encoding, return the original
        let allowParens = (format == .rfc1738)

        @inline(__always)
        func shouldPreserve(_ byte: UInt8) -> Bool {
            return isUnreserved(byte) || (allowParens && (byte == 0x28 || byte == 0x29))
        }

        var needsEncoding = false
        for byte in str.utf8 where !shouldPreserve(byte) {
            needsEncoding = true
            break
        }
        if !needsEncoding { return str }

        // Encode in one pass over UTF-8 bytes
        var out = String()
        out.reserveCapacity(str.utf8.count)  // good heuristic

        for byte in str.utf8 {
            if isUnreserved(byte) || (allowParens && (byte == 0x28 || byte == 0x29)) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += hexTable[Int(byte)]  // your precomputed "%XX"
            }
        }

        return format.formatter.apply(out)
    }

    @inline(__always)
    private static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x2D, 0x2E, 0x5F, 0x7E, 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    // MARK: - Escape

    /// A Swift representation of the deprecated JavaScript escape function
    /// https://developer.mozilla.org/en-US/docs/web/javascript/reference/global_objects/escape
    @available(*, deprecated, message: "Use addingPercentEncoding instead")
    @usableFromInline
    static func escape(_ string: String, format: Format = .rfc3986) -> String {
        _escape(string, format: format)
    }

    private static func _escape(_ str: String, format: Format) -> String {
        let allowParens = (format == .rfc1738)

        // Fast path: all ASCII + safe set ⇒ return as-is
        var needsEscaping = false
        for scalar in str.unicodeScalars {
            let scalarValue = scalar.value
            if scalarValue < 128 {
                if !isEscapeSafe(UInt8(scalarValue), allowParens: allowParens) {
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

        for scalar in str.unicodeScalars {
            let scalarValue = scalar.value
            if scalarValue < 128 {
                let byte = UInt8(scalarValue)
                if isEscapeSafe(byte, allowParens: allowParens) {
                    out.unicodeScalars.append(scalar)
                    continue
                }
            }
            if scalarValue < 256 {
                out += hexTable[Int(scalarValue)]  // "%XX"
            } else if scalarValue <= 0xFFFF {
                out.append("%u")
                appendHex4(scalarValue, to: &out)  // "%uXXXX"
            } else {
                // surrogate pair as two %u sequences
                let adj = scalarValue - 0x10000
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
    private static func isEscapeSafe(_ byte: UInt8, allowParens: Bool) -> Bool {
        switch byte {
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
    private static func hexDigit(_ value: UInt32) -> UInt8 {
        let nibble = value & 0xF
        return nibble < 10 ? (UInt8(48) + UInt8(nibble)) : (UInt8(55) + UInt8(nibble))  // '0'..'9','A'..'F'
    }

    @inline(__always)
    private static func appendHex4(_ value: UInt32, to out: inout String) {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes[0] = hexDigit(value >> 12)
        bytes[1] = hexDigit(value >> 8)
        bytes[2] = hexDigit(value >> 4)
        bytes[3] = hexDigit(value)
        // ASCII hex is valid UTF-8; use failable initializer and fallback to empty string if conversion fails.
        out += String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static let uEscapeRegex: NSRegularExpression = {
        // Constant, known-valid pattern; safe to force-try.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"%u([0-9A-Fa-f]{4})"#)
    }()
}

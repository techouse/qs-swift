import Foundation
import QsSwift

// Keep this in sync with your C# harness toggle
let percentEncodeBrackets = true

// Find test_cases.json (try a few common spots so you can run from repo root)
let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let jsonCandidates = [
    cwd.appendingPathComponent("Tools/QsSwiftComparison/js/test_cases.json"),
    cwd.appendingPathComponent("js/test_cases.json"),
]

guard let jsonURL = jsonCandidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
    fputs("Missing test_cases.json (tried: \(jsonCandidates.map(\.path).joined(separator: ", ")))\n", stderr)
    exit(1)
}

let data = try Data(contentsOf: jsonURL)
guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
    fputs("Could not parse test_cases.json as array of objects.\n", stderr)
    exit(1)
}

// NSNumber can be a Bool—distinguish it so we don't stringify booleans.
@inline(__always)
func isBoolNSNumber(_ n: NSNumber) -> Bool {
    CFGetTypeID(n) == CFBooleanGetTypeID()
}

// Recursively convert JSONSerialization output into the shapes Qs expects,
// while turning *numbers* into *strings*, like your C# helper does.
func normalizeJSON(_ v: Any) -> Any? {
    switch v {
    case is NSNull:
        return NSNull()
    case let n as NSNumber:
        return isBoolNSNumber(n) ? n.boolValue : n.stringValue
    case let s as String:
        return s
    case let a as [Any]:
        return a.map(normalizeJSON)
    case let d as [String: Any]:
        var out: [String: Any?] = [:]
        out.reserveCapacity(d.count)
        for (k, vv) in d {
            out[k] = normalizeJSON(vv)
        }
        return out
    default:
        return String(describing: v)
    }
}

@inline(__always)
private func jsonEscape(_ s: String) -> String {
    var out = "\""
    out.reserveCapacity(s.utf8.count + 2)
    for scalar in s.unicodeScalars {
        switch scalar.value {
        case 0x22: out += "\\\""  // '"'
        case 0x5C: out += "\\\\"  // '\\'
        case 0x08: out += "\\b"
        case 0x0C: out += "\\f"
        case 0x0A: out += "\\n"
        case 0x0D: out += "\\r"
        case 0x09: out += "\\t"
        case 0x00..<0x20:
            let hex = String(scalar.value, radix: 16, uppercase: true)
            out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}

@inline(__always)
private func writeJSON(_ v: Any, into out: inout String) {
    // NSNull
    if v is NSNull {
        out += "null"
        return
    }

    // Bool (NSNumber may bridge from Bool)
    if let b = v as? Bool {
        out += b ? "true" : "false"
        return
    }
    if let n = v as? NSNumber {
        // Distinguish Bool-backed NSNumber from numeric
        if isBoolNSNumber(n) {
            out += n.boolValue ? "true" : "false"
            return
        } else {
            // Use a locale-independent representation
            out += String(format: "%g", n.doubleValue)
            return
        }
    }

    // String
    if let s = v as? String {
        out += jsonEscape(s)
        return
    }

    // Array
    if let a = v as? [Any] {
        out += "["
        for i in a.indices {
            if i > 0 { out += "," }
            writeJSON(a[i], into: &out)
        }
        out += "]"
        return
    } else if let a = v as? NSArray {
        out += "["
        for i in 0..<a.count {
            if i > 0 { out += "," }
            writeJSON(a[i], into: &out)
        }
        out += "]"
        return
    }

    // Object / dictionary — sort keys lexicographically for determinism
    if let d = v as? [String: Any] {
        out += "{"
        let keys = d.keys.sorted()
        for (i, k) in keys.enumerated() {
            if i > 0 { out += "," }
            out += jsonEscape(k)
            out += ":"
            writeJSON(d[k] as Any, into: &out)
        }
        out += "}"
        return
    } else if let nd = v as? NSDictionary {
        var tmp: [String: Any] = [:]
        nd.forEach { (key: Any, val: Any) in
            if let ks = key as? String { tmp[ks] = val } else { tmp[String(describing: key)] = val }
        }
        out += "{"
        let keys = tmp.keys.sorted()
        for (i, k) in keys.enumerated() {
            if i > 0 { out += "," }
            out += jsonEscape(k)
            out += ":"
            writeJSON(tmp[k] as Any, into: &out)
        }
        out += "}"
        return
    }

    // Fallback: stringify scalars we don’t explicitly handle
    out += jsonEscape(String(describing: v))
}

@inline(__always)
func canonJSON(_ v: Any) -> String {
    var s = ""
    writeJSON(v, into: &s)
    return s
}

// Run the cases
for c in raw {
    let encodedIn = c["encoded"] as? String
    let dataIn = c["data"].flatMap(normalizeJSON)

    // Encode
    let encodedOut: String = {
        let s = try! Qs.encode((dataIn as? [String: Any?]) ?? [:])
        return percentEncodeBrackets
            ? s.replacingOccurrences(of: "[", with: "%5B").replacingOccurrences(of: "]", with: "%5D") : s
    }()

    print("Encoded: \(encodedOut)")

    // Decode (from 'encoded' in the fixture)
    if let encoded = encodedIn {
        let decoded = try! Qs.decode(encoded)
        print("Decoded: \(canonJSON(decoded))")
    } else {
        // If a case doesn’t have 'encoded', decode what we just encoded (parity)
        let decoded = try! Qs.decode(encodedOut)
        print("Decoded: \(canonJSON(decoded))")
    }
}

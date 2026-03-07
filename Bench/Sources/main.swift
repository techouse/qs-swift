import Foundation
import QsSwift

#if canImport(ObjectiveC)
    import QsObjC
#endif

func benchCommaList(_ N: Int) throws {
    var parts: [String] = []
    parts.reserveCapacity(N)
    for i in 0..<N { parts.append("a[]=\(i),\(i+1),\(i+2)") }
    let qs = parts.joined(separator: "&")

    let t0 = DispatchTime.now()
    let result = try Qs.decode(qs, options: .init(comma: true, parameterLimit: .max))
    let elapsed =
        Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000

    print((result["a"] as? [Any])?.count ?? 0)
    print(String(format: "elapsed: %.6f s", elapsed))
}

func benchDeep(_ N: Int) throws {
    var s = "foo"
    for _ in 0..<N { s += "[p]" }
    s += "=x"

    let t0 = DispatchTime.now()
    let result = try Qs.decode(s, options: .init(depth: max(N, 5)))
    let elapsed =
        Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000

    print(result.keys.contains("foo"))
    print(String(format: "elapsed: %.6f s", elapsed))
}

private struct DeepEncodeCase {
    let depth: Int
    let iterations: Int
}

private struct DecodeSnapshotCase {
    let name: String
    let count: Int
    let comma: Bool
    let utf8Sentinel: Bool
    let valueLen: Int
    let iterations: Int
}

private let deepEncodeCases: [DeepEncodeCase] = [
    .init(depth: 2000, iterations: 20),
    .init(depth: 5000, iterations: 20),
    .init(depth: 12000, iterations: 8),
]

private let decodeSnapshotCases: [DecodeSnapshotCase] = [
    .init(name: "C1", count: 100, comma: false, utf8Sentinel: false, valueLen: 8, iterations: 120),
    .init(name: "C2", count: 1000, comma: false, utf8Sentinel: false, valueLen: 40, iterations: 16),
    .init(name: "C3", count: 1000, comma: true, utf8Sentinel: true, valueLen: 40, iterations: 16),
]

private let sampleCount = 7
private let warmupCount = 5

private enum BenchError: Error {
    case objcEncodeFailed(depth: Int)
    case objcDecodeFailed(caseName: String)
}

private func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty, "median requires at least one value")
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

@inline(__always)
private func runGcPause() {
    Thread.sleep(forTimeInterval: 0.025)
}

private func buildNestedSwift(depth: Int) -> [String: Any] {
    var current: [String: Any] = ["leaf": "x"]
    for _ in 0..<depth {
        current = ["a": current]
    }
    return current
}

private func makeValue(length: Int, seed: Int) -> String {
    var out = String()
    out.reserveCapacity(length)

    var state: UInt32 =
        UInt32(truncatingIfNeeded: seed) &* 2_654_435_761 &+ 1_013_904_223

    for _ in 0..<length {
        state ^= state &<< 13
        state ^= state &>> 17
        state ^= state &<< 5

        let x = Int(state % 62)
        let codePoint: UInt32
        if x < 10 {
            codePoint = UInt32(0x30 + x)
        } else if x < 36 {
            codePoint = UInt32(0x41 + (x - 10))
        } else {
            codePoint = UInt32(0x61 + (x - 36))
        }

        out.append(Character(UnicodeScalar(codePoint)!))
    }

    return out
}

private func buildDecodeQuery(
    count: Int,
    commaLists: Bool,
    utf8Sentinel: Bool,
    valueLen: Int
) -> String {
    var parts: [String] = []
    parts.reserveCapacity(count + (utf8Sentinel ? 1 : 0))

    if utf8Sentinel {
        parts.append("utf8=%E2%9C%93")
    }

    for i in 0..<count {
        let key = "k\(i)"
        let value = (commaLists && i % 10 == 0) ? "a,b,c" : makeValue(length: valueLen, seed: i)
        parts.append("\(key)=\(value)")
    }

    return parts.joined(separator: "&")
}

#if canImport(ObjectiveC)
    private func buildNestedObjC(depth: Int) -> NSDictionary {
        var current: NSDictionary = NSDictionary(dictionary: ["leaf": "x"])
        for _ in 0..<depth {
            current = NSDictionary(object: current, forKey: "a" as NSString)
        }
        return current
    }
#endif

private func measureSwiftEncodeDeep(depth: Int, iterations: Int) throws -> (msPerOp: Double, outLength: Int) {
    let payload = buildNestedSwift(depth: depth)
    let options = EncodeOptions(encode: false)

    for _ in 0..<warmupCount {
        _ = try Qs.encode(payload, options: options)
    }

    var samples: [Double] = []
    samples.reserveCapacity(sampleCount)
    var outLength = 0

    for _ in 0..<sampleCount {
        runGcPause()
        let start = DispatchTime.now().uptimeNanoseconds
        var encoded = ""
        for _ in 0..<iterations {
            encoded = try Qs.encode(payload, options: options)
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        samples.append(elapsedMs / Double(iterations))
        outLength = encoded.count
    }

    return (median(samples), outLength)
}

#if canImport(ObjectiveC)
    private func measureObjCEncodeDeep(depth: Int, iterations: Int) throws -> (msPerOp: Double, outLength: Int) {
        let payload = buildNestedObjC(depth: depth)
        let options = EncodeOptionsObjC()
        options.encode = false

        for _ in 0..<warmupCount {
            _ = QsBridge.encode(payload, options: options, error: nil)
        }

        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        var outLength = 0

        for _ in 0..<sampleCount {
            runGcPause()
            let start = DispatchTime.now().uptimeNanoseconds
            var encoded: NSString?
            for _ in 0..<iterations {
                encoded = QsBridge.encode(payload, options: options, error: nil)
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            samples.append(elapsedMs / Double(iterations))

            guard let encoded else {
                throw BenchError.objcEncodeFailed(depth: depth)
            }
            outLength = (encoded as String).count
        }

        return (median(samples), outLength)
    }
#endif

private func perfSnapshot() throws {
    print("QsSwiftBench perf snapshot (median of 7 samples)")
    print("Encode (encode=false, deep nesting):")

    for c in deepEncodeCases {
        let (ms, outLength) = try measureSwiftEncodeDeep(depth: c.depth, iterations: c.iterations)
        print(String(format: "  swift depth=%5d: %8.3f ms/op | len=%d", c.depth, ms, outLength))
    }

    #if canImport(ObjectiveC)
        print("Encode via ObjC bridge (QsBridge.encode, deep nesting):")
        for c in deepEncodeCases {
            let (ms, outLength) = try measureObjCEncodeDeep(depth: c.depth, iterations: c.iterations)
            print(String(format: "  objc  depth=%5d: %8.3f ms/op | len=%d", c.depth, ms, outLength))
        }
    #endif
}

private func measureSwiftDecodeSnapshot(
    _ c: DecodeSnapshotCase
) throws -> (msPerOp: Double, keyCount: Int) {
    let query = buildDecodeQuery(
        count: c.count,
        commaLists: c.comma,
        utf8Sentinel: c.utf8Sentinel,
        valueLen: c.valueLen
    )

    let options = DecodeOptions(
        charsetSentinel: c.utf8Sentinel,
        comma: c.comma,
        parameterLimit: .max,
        throwOnLimitExceeded: false
    )

    for _ in 0..<warmupCount {
        _ = try Qs.decode(query, options: options)
    }

    var samples: [Double] = []
    samples.reserveCapacity(sampleCount)
    var keyCount = 0

    for _ in 0..<sampleCount {
        runGcPause()
        let start = DispatchTime.now().uptimeNanoseconds
        var decoded: [String: Any] = [:]
        for _ in 0..<c.iterations {
            decoded = try Qs.decode(query, options: options)
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        samples.append(elapsedMs / Double(c.iterations))
        keyCount = decoded.count
    }

    return (median(samples), keyCount)
}

#if canImport(ObjectiveC)
    private func measureObjCDecodeSnapshot(
        _ c: DecodeSnapshotCase
    ) throws -> (msPerOp: Double, keyCount: Int) {
        let query = buildDecodeQuery(
            count: c.count,
            commaLists: c.comma,
            utf8Sentinel: c.utf8Sentinel,
            valueLen: c.valueLen
        )

        let options = DecodeOptionsObjC()
        options.comma = c.comma
        options.parseLists = true
        options.parameterLimit = .max
        options.throwOnLimitExceeded = false
        options.interpretNumericEntities = false
        options.charsetSentinel = c.utf8Sentinel
        options.ignoreQueryPrefix = false

        for _ in 0..<warmupCount {
            _ = QsBridge.decode(query as NSString, options: options, error: nil)
        }

        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        var keyCount = 0

        for _ in 0..<sampleCount {
            runGcPause()
            let start = DispatchTime.now().uptimeNanoseconds
            var decoded: NSDictionary?
            for _ in 0..<c.iterations {
                decoded = QsBridge.decode(query as NSString, options: options, error: nil)
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            samples.append(elapsedMs / Double(c.iterations))

            guard let decoded else {
                throw BenchError.objcDecodeFailed(caseName: c.name)
            }
            keyCount = decoded.count
        }

        return (median(samples), keyCount)
    }
#endif

private func perfDecodeSnapshot() throws {
    print("QsSwiftBench decode snapshot (median of 7 samples)")
    print("Decode (public API):")

    for c in decodeSnapshotCases {
        let (ms, keyCount) = try measureSwiftDecodeSnapshot(c)
        print(
            String(
                format:
                    "  swift-decode %@ count=%d comma=%@ utf8=%@ len=%d: %.3f ms/op | keys=%d",
                c.name as NSString,
                c.count,
                String(c.comma) as NSString,
                String(c.utf8Sentinel) as NSString,
                c.valueLen,
                ms,
                keyCount
            )
        )
    }

    #if canImport(ObjectiveC)
        for c in decodeSnapshotCases {
            let (ms, keyCount) = try measureObjCDecodeSnapshot(c)
            print(
                String(
                    format:
                        "  objc-decode %@ count=%d comma=%@ utf8=%@ len=%d: %.3f ms/op | keys=%d",
                    c.name as NSString,
                    c.count,
                    String(c.comma) as NSString,
                    String(c.utf8Sentinel) as NSString,
                    c.valueLen,
                    ms,
                    keyCount
                )
            )
        }
    #endif
}

// --- entry point ---
let scenario = CommandLine.arguments.dropFirst().first?.lowercased() ?? "list"
let N = Int(ProcessInfo.processInfo.environment["N"] ?? "") ?? 2000

switch scenario {
case "deep": try benchDeep(N)
case "perf", "perf-encode-deep": try perfSnapshot()
case "perf-decode", "perf-decode-snapshot": try perfDecodeSnapshot()
case "perf-all":
    try perfSnapshot()
    try perfDecodeSnapshot()
default: try benchCommaList(N)
}

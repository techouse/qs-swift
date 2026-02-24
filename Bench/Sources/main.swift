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

private let deepEncodeCases: [DeepEncodeCase] = [
    .init(depth: 2000, iterations: 20),
    .init(depth: 5000, iterations: 20),
    .init(depth: 12000, iterations: 8),
]

private let sampleCount = 7
private let warmupCount = 5

private enum BenchError: Error {
    case objcEncodeFailed(depth: Int)
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

#if canImport(ObjectiveC)
    private func buildNestedObjC(depth: Int) -> NSDictionary {
        var current: Any = NSDictionary(dictionary: ["leaf": "x"])
        for _ in 0..<depth {
            current = NSDictionary(object: current, forKey: "a" as NSString)
        }
        return current as! NSDictionary
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

// --- entry point ---
let scenario = CommandLine.arguments.dropFirst().first?.lowercased() ?? "list"
let N = Int(ProcessInfo.processInfo.environment["N"] ?? "") ?? 2000

switch scenario {
case "deep": try benchDeep(N)
case "perf", "perf-encode-deep": try perfSnapshot()
default: try benchCommaList(N)
}

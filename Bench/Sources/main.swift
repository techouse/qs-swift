import Foundation
import Qs

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

// --- entry point ---
let scenario = CommandLine.arguments.dropFirst().first?.lowercased() ?? "list"
let N = Int(ProcessInfo.processInfo.environment["N"] ?? "") ?? 2000

switch scenario {
case "deep": try benchDeep(N)
default: try benchCommaList(N)
}

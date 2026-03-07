import Foundation

public struct PerfSummary: Decodable {
    public struct CaseRecord: Decodable {
        public let runtime: String
        public let depth: Int
        public let msPerOpMedian: Double

        private enum CodingKeys: String, CodingKey {
            case runtime
            case depth
            case msPerOpMedian = "ms_per_op_median"
        }
    }

    public let cases: [CaseRecord]
}

public struct DecodePerfSummary: Decodable {
    public struct CaseRecord: Decodable {
        public let runtime: String
        public let name: String
        public let count: Int
        public let comma: Bool
        public let utf8: Bool
        public let len: Int
        public let msPerOpMedian: Double

        private enum CodingKeys: String, CodingKey {
            case runtime
            case name
            case count
            case comma
            case utf8
            case len
            case msPerOpMedian = "ms_per_op_median"
        }
    }

    public let cases: [CaseRecord]
}

public struct BenchCaseKey: Hashable {
    public let runtime: String
    public let depth: Int

    public init(runtime: String, depth: Int) {
        self.runtime = runtime
        self.depth = depth
    }
}

public struct DecodeBenchCaseKey: Hashable {
    public let runtime: String
    public let name: String
    public let count: Int
    public let comma: Bool
    public let utf8: Bool
    public let len: Int

    public init(runtime: String, name: String, count: Int, comma: Bool, utf8: Bool, len: Int) {
        self.runtime = runtime
        self.name = name
        self.count = count
        self.comma = comma
        self.utf8 = utf8
        self.len = len
    }
}

public struct DecodePerfCaseSpec: Sendable {
    public let name: String
    public let count: Int
    public let comma: Bool
    public let utf8: Bool
    public let len: Int

    public init(name: String, count: Int, comma: Bool, utf8: Bool, len: Int) {
        self.name = name
        self.count = count
        self.comma = comma
        self.utf8 = utf8
        self.len = len
    }
}

public let deepEncodePerfCases = [2000, 5000, 12000]
public let decodePerfCases: [DecodePerfCaseSpec] = [
    .init(name: "C1", count: 100, comma: false, utf8: false, len: 8),
    .init(name: "C2", count: 1000, comma: false, utf8: false, len: 40),
    .init(name: "C3", count: 1000, comma: true, utf8: true, len: 40),
]

private let benchOutputRegex: NSRegularExpression = {
    do {
        return try NSRegularExpression(
            pattern: #"^\s*(swift|objc)\s+depth=\s*(\d+):\s*([0-9.]+)\s*ms/op"#,
            options: []
        )
    } catch {
        fatalError("Invalid bench output regex literal: \(error)")
    }
}()

private let decodeBenchOutputRegex: NSRegularExpression = {
    do {
        return try NSRegularExpression(
            pattern:
                #"^\s*(swift|objc)-decode\s+(C[0-9]+)\s+count=(\d+)\s+comma=(true|false)\s+utf8=(true|false)\s+len=(\d+):\s*([0-9.]+)\s*ms/op"#,
            options: []
        )
    } catch {
        fatalError("Invalid decode bench output regex literal: \(error)")
    }
}()

/// Resolves repo root by trimming `file -> TestSupport -> Tests -> repo root` from `#filePath`.
/// This depends on this file remaining under `Tests/TestSupport`; if moved, update this function.
public func repoRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

public func runCommand(
    _ executable: String,
    args: [String],
    cwd: URL,
    errorDomain: String = "PerfGuardrailTests",
    tempPrefix: String = "qs-perf"
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    process.currentDirectoryURL = cwd

    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory
        .appendingPathComponent("\(tempPrefix)-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempDir) }

    let stdoutURL = tempDir.appendingPathComponent("stdout.log")
    let stderrURL = tempDir.appendingPathComponent("stderr.log")
    fileManager.createFile(atPath: stdoutURL.path, contents: nil)
    fileManager.createFile(atPath: stderrURL.path, contents: nil)

    let stdout = try FileHandle(forWritingTo: stdoutURL)
    let stderr = try FileHandle(forWritingTo: stderrURL)
    defer {
        try? stdout.close()
        try? stderr.close()
    }
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let outData = try Data(contentsOf: stdoutURL)
    let errData = try Data(contentsOf: stderrURL)
    let out = String(decoding: outData, as: UTF8.self)
    let err = String(decoding: errData, as: UTF8.self)

    if process.terminationStatus != 0 {
        throw NSError(
            domain: errorDomain,
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Command failed: \(executable) \(args.joined(separator: " "))\n\(err)"
            ]
        )
    }

    return out
}

public func loadBaseline(runtime: String, root: URL = repoRootURL()) throws -> [Int: Double] {
    let baselineURL = root.appendingPathComponent(
        "Bench/baselines/encode_deep_snapshot_baseline.json"
    )
    let data = try Data(contentsOf: baselineURL)
    let summary = try JSONDecoder().decode(PerfSummary.self, from: data)

    return summary.cases.reduce(into: [Int: Double]()) { acc, entry in
        guard entry.runtime == runtime else { return }
        acc[entry.depth] = entry.msPerOpMedian
    }
}

public func loadDecodeBaseline(
    runtime: String,
    root: URL = repoRootURL()
) throws -> [DecodeBenchCaseKey: Double] {
    let baselineURL = root.appendingPathComponent(
        "Bench/baselines/decode_snapshot_baseline.json"
    )
    let data = try Data(contentsOf: baselineURL)
    let summary = try JSONDecoder().decode(DecodePerfSummary.self, from: data)

    return summary.cases.reduce(into: [DecodeBenchCaseKey: Double]()) { acc, entry in
        guard entry.runtime == runtime else { return }
        let key = DecodeBenchCaseKey(
            runtime: entry.runtime,
            name: entry.name,
            count: entry.count,
            comma: entry.comma,
            utf8: entry.utf8,
            len: entry.len
        )
        acc[key] = entry.msPerOpMedian
    }
}

public func parseBenchOutput(_ output: String) throws -> [BenchCaseKey: Double] {
    var result: [BenchCaseKey: Double] = [:]
    for line in output.split(whereSeparator: \.isNewline) {
        let text = String(line)
        let range = NSRange(location: 0, length: text.utf16.count)
        guard
            let match = benchOutputRegex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges == 4,
            let runtimeRange = Range(match.range(at: 1), in: text),
            let depthRange = Range(match.range(at: 2), in: text),
            let msRange = Range(match.range(at: 3), in: text),
            let depth = Int(text[depthRange]),
            let ms = Double(text[msRange])
        else {
            continue
        }

        result[BenchCaseKey(runtime: String(text[runtimeRange]), depth: depth)] = ms
    }

    return result
}

public func parseDecodeBenchOutput(_ output: String) throws -> [DecodeBenchCaseKey: Double] {
    var result: [DecodeBenchCaseKey: Double] = [:]
    for line in output.split(whereSeparator: \.isNewline) {
        let text = String(line)
        let range = NSRange(location: 0, length: text.utf16.count)
        guard
            let match = decodeBenchOutputRegex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges == 8,
            let runtimeRange = Range(match.range(at: 1), in: text),
            let nameRange = Range(match.range(at: 2), in: text),
            let countRange = Range(match.range(at: 3), in: text),
            let commaRange = Range(match.range(at: 4), in: text),
            let utf8Range = Range(match.range(at: 5), in: text),
            let lenRange = Range(match.range(at: 6), in: text),
            let msRange = Range(match.range(at: 7), in: text),
            let count = Int(text[countRange]),
            let len = Int(text[lenRange]),
            let ms = Double(text[msRange])
        else {
            continue
        }

        let key = DecodeBenchCaseKey(
            runtime: String(text[runtimeRange]),
            name: String(text[nameRange]),
            count: count,
            comma: String(text[commaRange]) == "true",
            utf8: String(text[utf8Range]) == "true",
            len: len
        )
        result[key] = ms
    }

    return result
}

public func perfGuardrailsEnabled(extraFlag: String) -> Bool {
    let env = ProcessInfo.processInfo.environment
    let enabledByFlag = env["QS_ENABLE_PERF_GUARDRAILS"] == "1" || env[extraFlag] == "1"
    guard enabledByFlag else { return false }

    #if DEBUG
        return env["QS_PERF_ALLOW_DEBUG"] == "1"
    #else
        return true
    #endif
}

public func perfTolerancePct() -> Double {
    let raw = ProcessInfo.processInfo.environment["QS_PERF_REGRESSION_TOLERANCE_PCT"] ?? ""
    return Double(raw) ?? 20.0
}

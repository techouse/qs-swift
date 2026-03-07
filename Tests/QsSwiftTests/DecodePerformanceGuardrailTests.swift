import Foundation
import QsTestSupport

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct DecodePerformanceGuardrailTests {
    @Test(
        "perf guardrail (opt-in): Swift decode snapshot",
        .timeLimit(.minutes(10)),
        .enabled(
            if: perfGuardrailsEnabled(extraFlag: "QS_ENABLE_SWIFT_DECODE_PERF_GUARDRAILS"),
            "Perf guardrails not enabled — skipping")
    )
    func perfGuardrail_swiftDecodeSnapshot() throws {
        let root = repoRootURL()
        _ = try runCommand(
            "/usr/bin/env",
            args: ["swift", "build", "-c", "release", "--package-path", "Bench", "-q"],
            cwd: root,
            errorDomain: "DecodePerformanceGuardrailTests",
            tempPrefix: "qsswift-decode-perf"
        )

        let benchOutput = try runCommand(
            root.appendingPathComponent("Bench/.build/release/QsSwiftBench").path,
            args: ["perf-decode"],
            cwd: root,
            errorDomain: "DecodePerformanceGuardrailTests",
            tempPrefix: "qsswift-decode-perf"
        )
        let measured = try parseDecodeBenchOutput(benchOutput)

        let baseline = try loadDecodeBaseline(runtime: "swift", root: root)
        let tolerance = perfTolerancePct() / 100.0

        for c in decodePerfCases {
            let key = DecodeBenchCaseKey(
                runtime: "swift",
                name: c.name,
                count: c.count,
                comma: c.comma,
                utf8: c.utf8,
                len: c.len
            )

            guard let baselineMs = baseline[key] else {
                Issue.record("Missing Swift decode perf baseline for \(c.name)")
                continue
            }
            guard let measuredMs = measured[key] else {
                Issue.record("Missing Swift decode perf measurement for \(c.name)")
                continue
            }

            let allowedMs = baselineMs * (1.0 + tolerance)
            #expect(
                measuredMs <= allowedMs,
                "Swift decode perf guardrail failed for \(c.name): measuredMs=\(measuredMs), allowedMs=\(allowedMs), baselineMs=\(baselineMs)"
            )
        }
    }
}

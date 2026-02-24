import Foundation
import QsTestSupport

#if canImport(Testing)
    import Testing
#else
    #error("The swift-testing package is required to build tests on Swift 5.x")
#endif

struct EncodePerformanceGuardrailTests {
    @Test(
        "perf guardrail (opt-in): Swift deep encode snapshot",
        .timeLimit(.minutes(10)),
        .enabled(
            if: perfGuardrailsEnabled(extraFlag: "QS_ENABLE_SWIFT_PERF_GUARDRAILS"),
            "Perf guardrails not enabled — skipping")
    )
    func perfGuardrail_swiftDeepEncode() throws {
        let root = repoRootURL()
        _ = try runCommand(
            "/usr/bin/env",
            args: ["swift", "build", "-c", "release", "--package-path", "Bench", "-q"],
            cwd: root,
            errorDomain: "EncodePerformanceGuardrailTests",
            tempPrefix: "qsswift-perf"
        )

        let benchOutput = try runCommand(
            root.appendingPathComponent("Bench/.build/release/QsSwiftBench").path,
            args: ["perf"],
            cwd: root,
            errorDomain: "EncodePerformanceGuardrailTests",
            tempPrefix: "qsswift-perf"
        )
        let measured = try parseBenchOutput(benchOutput)

        let baseline = try loadBaseline(runtime: "swift", root: root)
        let tolerance = perfTolerancePct() / 100.0

        for depth in deepEncodePerfCases {
            guard let baselineMs = baseline[depth] else {
                Issue.record("Missing Swift perf baseline for depth=\(depth)")
                continue
            }
            guard let measuredMs = measured[BenchCaseKey(runtime: "swift", depth: depth)] else {
                Issue.record("Missing Swift perf measurement for depth=\(depth)")
                continue
            }

            let allowedMs = baselineMs * (1.0 + tolerance)
            #expect(
                measuredMs <= allowedMs,
                "Swift perf guardrail failed at depth=\(depth): measuredMs=\(measuredMs), allowedMs=\(allowedMs), baselineMs=\(baselineMs)"
            )
        }
    }
}

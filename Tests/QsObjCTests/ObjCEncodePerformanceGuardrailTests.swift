#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import QsTestSupport
    import Testing

    struct ObjCEncodePerformanceGuardrailTests {
        @Test("perf guardrail (opt-in): ObjC bridge deep encode snapshot")
        func perfGuardrail_objcDeepEncode() throws {
            guard perfGuardrailsEnabled(extraFlag: "QS_ENABLE_OBJC_PERF_GUARDRAILS") else { return }

            let root = repoRootURL()
            _ = try runCommand(
                "/usr/bin/env",
                args: ["swift", "build", "-c", "release", "--package-path", "Bench", "-q"],
                cwd: root,
                errorDomain: "ObjCEncodePerformanceGuardrailTests",
                tempPrefix: "qsobjc-perf"
            )

            let benchOutput = try runCommand(
                root.appendingPathComponent("Bench/.build/release/QsSwiftBench").path,
                args: ["perf"],
                cwd: root,
                errorDomain: "ObjCEncodePerformanceGuardrailTests",
                tempPrefix: "qsobjc-perf"
            )
            let measured = try parseBenchOutput(benchOutput)

            let baseline = try loadBaseline(runtime: "objc", root: root)
            let tolerance = perfTolerancePct() / 100.0

            for depth in deepEncodePerfCases {
                guard let baselineMs = baseline[depth] else {
                    Issue.record("Missing ObjC perf baseline for depth=\(depth)")
                    continue
                }
                guard let measuredMs = measured[BenchCaseKey(runtime: "objc", depth: depth)] else {
                    Issue.record("Missing ObjC perf measurement for depth=\(depth)")
                    continue
                }

                let allowedMs = baselineMs * (1.0 + tolerance)
                #expect(
                    measuredMs <= allowedMs,
                    "ObjC perf guardrail failed at depth=\(depth): measuredMs=\(measuredMs), baselineMs=\(baselineMs), tolerance=\(tolerance), allowedMs=\(allowedMs)"
                )
            }
        }
    }
#endif

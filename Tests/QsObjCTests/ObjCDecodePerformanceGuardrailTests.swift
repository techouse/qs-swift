#if canImport(ObjectiveC) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import Foundation
    import QsTestSupport
    import Testing

    struct ObjCDecodePerformanceGuardrailTests {
        @Test(
            "perf guardrail (opt-in): ObjC bridge decode snapshot",
            .timeLimit(.minutes(10)),
            .enabled(
                if: perfGuardrailsEnabled(extraFlag: "QS_ENABLE_OBJC_DECODE_PERF_GUARDRAILS"),
                "Perf guardrails not enabled — skipping")
        )
        func perfGuardrail_objcDecodeSnapshot() throws {
            let root = repoRootURL()
            _ = try runCommand(
                "/usr/bin/env",
                args: ["swift", "build", "-c", "release", "--package-path", "Bench", "-q"],
                cwd: root,
                errorDomain: "ObjCDecodePerformanceGuardrailTests",
                tempPrefix: "qsobjc-decode-perf"
            )

            let benchOutput = try runCommand(
                root.appendingPathComponent("Bench/.build/release/QsSwiftBench").path,
                args: ["perf-decode"],
                cwd: root,
                errorDomain: "ObjCDecodePerformanceGuardrailTests",
                tempPrefix: "qsobjc-decode-perf"
            )
            let measured = try parseDecodeBenchOutput(benchOutput)

            let baseline = try loadDecodeBaseline(runtime: "objc", root: root)
            let tolerance = perfTolerancePct() / 100.0

            for c in decodePerfCases {
                let key = DecodeBenchCaseKey(
                    runtime: "objc",
                    name: c.name,
                    count: c.count,
                    comma: c.comma,
                    utf8: c.utf8,
                    len: c.len
                )

                guard let baselineMs = baseline[key] else {
                    Issue.record("Missing ObjC decode perf baseline for \(c.name)")
                    continue
                }
                guard let measuredMs = measured[key] else {
                    Issue.record("Missing ObjC decode perf measurement for \(c.name)")
                    continue
                }

                let allowedMs = baselineMs * (1.0 + tolerance)
                #expect(
                    measuredMs <= allowedMs,
                    "ObjC decode perf guardrail failed for \(c.name): measuredMs=\(measuredMs), baselineMs=\(baselineMs), tolerance=\(tolerance), allowedMs=\(allowedMs)"
                )
            }
        }
    }
#endif

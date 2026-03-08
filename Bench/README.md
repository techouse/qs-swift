# QsSwiftBench

Standalone benchmark harness for `QsSwift` / `QsObjC`.

## Scenarios

- `list`: large comma-list decode payload.
- `deep`: deep decode key path payload (`foo[p][p]...`).
- `perf`: encode deep snapshot parity matrix (Swift + ObjC bridge).
- `perf-decode`: decode C1/C2/C3 snapshot parity matrix (Swift + ObjC bridge).

`perf` uses:
- depths: `2000`, `5000`, `12000`
- iterations: `20`, `20`, `8`
- statistic: median of `7` samples

## Quick start

```bash
cd Bench
swift build -c release

# Decode micro benches
.build/release/QsSwiftBench list
N=5000 .build/release/QsSwiftBench deep

# Encode deep snapshot (Swift + ObjC bridge)
.build/release/QsSwiftBench perf

# Decode snapshot (C1/C2/C3, Swift + ObjC bridge)
.build/release/QsSwiftBench perf-decode
```

## Snapshot compare workflow

Run repeated snapshots and emit a JSON summary:

```bash
./scripts/perf_compare.sh --scenario encode --runs 3 --output /tmp/qs_swift_perf_encode.json
./scripts/perf_compare.sh --scenario decode --runs 3 --output /tmp/qs_swift_perf_decode.json
```

Compare against committed baseline:

```bash
./scripts/perf_compare.sh \
  --scenario encode \
  --runs 3 \
  --output /tmp/qs_swift_perf_encode.json \
  --compare ./baselines/encode_deep_snapshot_baseline.json

./scripts/perf_compare.sh \
  --scenario decode \
  --runs 3 \
  --output /tmp/qs_swift_perf_decode.json \
  --compare ./baselines/decode_snapshot_baseline.json
```

Baseline file:
- `./baselines/encode_deep_snapshot_baseline.json`
- `./baselines/decode_snapshot_baseline.json`

## Optional perf guardrail tests

These tests are opt-in and intended for release mode.

```bash
QS_ENABLE_PERF_GUARDRAILS=1 SWIFT_DETERMINISTIC_HASHING=1 swift test -c release -q \
  --filter PerformanceGuardrail
```

Debug override:

```bash
QS_ENABLE_PERF_GUARDRAILS=1 QS_PERF_ALLOW_DEBUG=1 SWIFT_DETERMINISTIC_HASHING=1 swift test -q \
  --filter PerformanceGuardrail
```

Tolerance override (`20` by default):

```bash
QS_PERF_REGRESSION_TOLERANCE_PCT=25 QS_ENABLE_PERF_GUARDRAILS=1 swift test -c release -q \
  --filter PerformanceGuardrail
```

## Makefile helpers

```bash
make help
make clean
make reset
make profile
make perf-snapshot
make perf-compare
```

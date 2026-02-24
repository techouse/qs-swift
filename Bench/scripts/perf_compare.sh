#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Bench/scripts/perf_compare.sh [--runs N] [--output FILE] [--compare FILE]

Run the QsSwiftBench deep encode snapshot multiple times, summarize medians across
runs (Swift + ObjC bridge), and optionally compare against a saved baseline JSON.

Options:
  --runs N       Number of full snapshot runs to execute (default: 3)
  --output FILE  Where to write summary JSON (default: /tmp/qs_swift_perf_<ts>.json)
  --compare FILE Compare current summary against a previous summary JSON
EOF
}

runs=3
output=""
compare=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --runs" >&2
        exit 2
      fi
      runs="${2:-}"
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --output" >&2
        exit 2
      fi
      output="${2:-}"
      shift 2
      ;;
    --compare)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --compare" >&2
        exit 2
      fi
      compare="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$runs" =~ ^[0-9]+$ ]] || [[ "$runs" -le 0 ]]; then
  echo "--runs must be a positive integer" >&2
  exit 2
fi

if [[ -z "$output" ]]; then
  output="/tmp/qs_swift_perf_$(date +%Y%m%d_%H%M%S).json"
fi

if [[ -n "$compare" && ! -f "$compare" ]]; then
  echo "--compare file does not exist: $compare" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN="${BENCH_DIR}/.build/release/QsSwiftBench"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

raw_jsonl="$tmpdir/raw.jsonl"

echo "Building QsSwiftBench (release) ..."
swift build -c release --package-path "$BENCH_DIR" >/dev/null

for run in $(seq 1 "$runs"); do
  echo "Running perf snapshot ($run/$runs) ..."
  snapshot_file="$tmpdir/snapshot_$run.txt"
  "$BIN" perf >"$snapshot_file"
  python3 - "$run" "$snapshot_file" >>"$raw_jsonl" <<'PY'
import json
import re
import sys

run = int(sys.argv[1])
path = sys.argv[2]

line_re = re.compile(
    r"^\s*(swift|objc)\s+depth=\s*(\d+):\s*([0-9.]+)\s*ms/op\s*\|\s*len=(\d+)\s*$"
)

with open(path, "r", encoding="utf-8") as f:
    for line in f:
        m = line_re.match(line)
        if m:
            runtime, depth, ms, out_len = m.groups()
            rec = {
                "run": run,
                "runtime": runtime,
                "depth": int(depth),
                "len": int(out_len),
                "ms_per_op": float(ms),
            }
            print(json.dumps(rec))
        elif "ms/op" in line:
            print(
                f"[perf_compare] warning: run={run} unmatched benchmark line: {line.rstrip()}",
                file=sys.stderr,
            )
PY
done

python3 - "$raw_jsonl" "$output" "$compare" <<'PY'
import json
import statistics
import sys
from collections import defaultdict

raw_path, out_path, compare_path = sys.argv[1], sys.argv[2], sys.argv[3]

records = []
with open(raw_path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            records.append(json.loads(line))

if not records:
    print("No benchmark records were parsed.", file=sys.stderr)
    sys.exit(1)

groups = defaultdict(list)
for rec in records:
    key = (rec["runtime"], rec["depth"], rec["len"])
    groups[key].append(rec)

cases = []
for (runtime, depth, out_len), items in sorted(groups.items(), key=lambda x: (x[0][0], x[0][1])):
    ms_values = [x["ms_per_op"] for x in items]
    cases.append(
        {
            "runtime": runtime,
            "depth": depth,
            "len": out_len,
            "runs": len(items),
            "ms_per_op_median": statistics.median(ms_values),
            "ms_per_op_values": ms_values,
        }
    )

summary = {
    "runs": len({r["run"] for r in records}),
    "cases": cases,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, sort_keys=True)

print(f"\nSaved summary: {out_path}")
print("\nCurrent medians:")
for case in cases:
    print(
        f"  {case['runtime']:5s} depth={case['depth']:5d},len={case['len']:6d}  "
        f"ms={case['ms_per_op_median']:.3f}"
    )

if compare_path:
    with open(compare_path, "r", encoding="utf-8") as f:
        baseline = json.load(f)

    baseline_map = {
        (c["runtime"], c["depth"], c.get("len", -1)): c
        for c in baseline.get("cases", [])
    }

    print(f"\nDelta vs baseline: {compare_path}")
    for case in cases:
        key_exact = (case["runtime"], case["depth"], case["len"])
        key_len_agnostic = (case["runtime"], case["depth"], -1)
        base = baseline_map.get(key_exact) or baseline_map.get(key_len_agnostic)
        if not base:
            continue

        base_ms = base.get("ms_per_op_median")
        if not base_ms:
            continue
        delta = ((case["ms_per_op_median"] / base_ms) - 1.0) * 100.0
        print(
            f"  {case['runtime']:5s} depth={case['depth']:5d},len={case['len']:6d}  "
            f"ms={delta:+.2f}%"
        )
PY

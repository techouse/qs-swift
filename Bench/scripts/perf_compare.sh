#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Bench/scripts/perf_compare.sh [--scenario encode|decode|all] [--runs N] [--output FILE] [--compare FILE]

Run the QsSwiftBench snapshot multiple times, summarize medians across runs
(Swift + ObjC bridge), and optionally compare against a saved baseline JSON.

Options:
  --scenario S   Snapshot scenario: encode, decode, or all (default: encode)
  --runs N       Number of full snapshot runs to execute (default: 3)
  --output FILE  Where to write summary JSON (default: /tmp/qs_swift_perf_<ts>.json)
  --compare FILE Compare current summary against a previous summary JSON
USAGE
}

runs=3
output=""
compare=""
scenario="encode"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --scenario" >&2
        exit 2
      fi
      scenario="${2:-}"
      shift 2
      ;;
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

case "$scenario" in
  encode) scenario_cmd="perf" ;;
  decode) scenario_cmd="perf-decode" ;;
  all) scenario_cmd="perf-all" ;;
  *)
    echo "--scenario must be one of: encode, decode, all" >&2
    exit 2
    ;;
esac

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
  echo "Running $scenario snapshot ($run/$runs) ..."
  snapshot_file="$tmpdir/snapshot_$run.txt"
  "$BIN" "$scenario_cmd" >"$snapshot_file"
  python3 - "$run" "$snapshot_file" >>"$raw_jsonl" <<'PY'
import json
import re
import sys

run = int(sys.argv[1])
path = sys.argv[2]

encode_re = re.compile(
    r"^\s*(swift|objc)\s+depth=\s*(\d+):\s*([0-9.]+)\s*ms/op\s*\|\s*len=(\d+)\s*$"
)
decode_re = re.compile(
    r"^\s*(swift|objc)-decode\s+(C[0-9]+)\s+count=(\d+)\s+comma=(true|false)\s+utf8=(true|false)\s+len=(\d+):\s*([0-9.]+)\s*ms/op\s*\|\s*keys=(\d+)\s*$"
)

with open(path, "r", encoding="utf-8") as f:
    for line in f:
        m_encode = encode_re.match(line)
        if m_encode:
            runtime, depth, ms, out_len = m_encode.groups()
            rec = {
                "run": run,
                "kind": "encode",
                "runtime": runtime,
                "depth": int(depth),
                "len": int(out_len),
                "ms_per_op": float(ms),
            }
            print(json.dumps(rec))
            continue

        m_decode = decode_re.match(line)
        if m_decode:
            runtime, name, count, comma, utf8, length, ms, key_count = m_decode.groups()
            rec = {
                "run": run,
                "kind": "decode",
                "runtime": runtime,
                "name": name,
                "count": int(count),
                "comma": comma == "true",
                "utf8": utf8 == "true",
                "len": int(length),
                "keys": int(key_count),
                "ms_per_op": float(ms),
            }
            print(json.dumps(rec))
            continue

        if "ms/op" in line:
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


def rec_key(rec):
    if rec["kind"] == "encode":
        return ("encode", rec["runtime"], rec["depth"], rec["len"])
    return (
        "decode",
        rec["runtime"],
        rec["name"],
        rec["count"],
        rec["comma"],
        rec["utf8"],
        rec["len"],
    )


def case_key(case):
    kind = case.get("kind")
    if kind is None:
        kind = "decode" if {"name", "count", "comma", "utf8"}.issubset(case) else "encode"
    if kind == "encode":
        return ("encode", case["runtime"], case["depth"], case.get("len", -1))
    return (
        "decode",
        case["runtime"],
        case["name"],
        case["count"],
        case["comma"],
        case["utf8"],
        case.get("len", -1),
    )


groups = defaultdict(list)
for rec in records:
    groups[rec_key(rec)].append(rec)

cases = []
for key, items in sorted(groups.items(), key=lambda x: x[0]):
    ms_values = [x["ms_per_op"] for x in items]
    kind = key[0]

    if kind == "encode":
        _, runtime, depth, out_len = key
        case = {
            "kind": "encode",
            "runtime": runtime,
            "depth": depth,
            "len": out_len,
        }
    else:
        _, runtime, name, count, comma, utf8, out_len = key
        case = {
            "kind": "decode",
            "runtime": runtime,
            "name": name,
            "count": count,
            "comma": comma,
            "utf8": utf8,
            "len": out_len,
        }

    case["runs"] = len(items)
    case["ms_per_op_median"] = statistics.median(ms_values)
    case["ms_per_op_values"] = ms_values
    cases.append(case)

summary = {
    "runs": len({r["run"] for r in records}),
    "cases": cases,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, sort_keys=True)

print(f"\nSaved summary: {out_path}")
print("\nCurrent medians:")
for case in cases:
    if case["kind"] == "encode":
        print(
            f"  encode {case['runtime']:5s} depth={case['depth']:5d},len={case['len']:6d}  "
            f"ms={case['ms_per_op_median']:.3f}"
        )
    else:
        print(
            f"  decode {case['runtime']:5s} {case['name']} count={case['count']:4d} "
            f"comma={str(case['comma']).lower():5s} utf8={str(case['utf8']).lower():5s} "
            f"len={case['len']:4d}  ms={case['ms_per_op_median']:.3f}"
        )

if compare_path:
    with open(compare_path, "r", encoding="utf-8") as f:
        baseline = json.load(f)

    baseline_map = {case_key(c): c for c in baseline.get("cases", [])}

    print(f"\nDelta vs baseline: {compare_path}")
    for case in cases:
        key = case_key(case)
        base = baseline_map.get(key)
        if not base:
            continue

        base_ms = base.get("ms_per_op_median")
        if not base_ms:
            continue
        delta = ((case["ms_per_op_median"] / base_ms) - 1.0) * 100.0

        if case["kind"] == "encode":
            print(
                f"  encode {case['runtime']:5s} depth={case['depth']:5d},len={case['len']:6d}  "
                f"ms={delta:+.2f}%"
            )
        else:
            print(
                f"  decode {case['runtime']:5s} {case['name']} count={case['count']:4d} "
                f"comma={str(case['comma']).lower():5s} utf8={str(case['utf8']).lower():5s} "
                f"len={case['len']:4d}  ms={delta:+.2f}%"
            )
PY

#!/usr/bin/env bash
set -euo pipefail

# Profile script for QsBench (in Bench/)
# Builds baseline and inline variants, then compares with hyperfine.

if ! command -v hyperfine >/dev/null 2>&1; then
  echo "hyperfine is not installed. Try: brew install hyperfine"
  exit 1
fi

# Resolve the Bench package directory from the script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"          # -> Bench/
BIN_BASE="${PKG_DIR}/.build/release/QsSwiftBench_base"
BIN_INLINE="${PKG_DIR}/.build/release/QsSwiftBench_inline"
BIN_OUT="${PKG_DIR}/.build/release/QsSwiftBench"

# Build baseline
swift build -c release --package-path "$PKG_DIR"
cp -f "$BIN_OUT" "$BIN_BASE"

# Build inline (with forced inlining flag)
swift build -c release -Xswiftc -DQSBENCH_INLINE --package-path "$PKG_DIR"
cp -f "$BIN_OUT" "$BIN_INLINE"

# Compare "list" scenario
hyperfine --warmup 3 -r 20 \
  "${BIN_BASE} list" \
  "${BIN_INLINE} list"

# Compare "deep" scenario (with a larger N)
hyperfine --warmup 3 -r 20 \
  "N=5000 ${BIN_BASE} deep" \
  "N=5000 ${BIN_INLINE} deep"

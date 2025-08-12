#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root from the script location (…/scripts -> repo root)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

# Defaults
CONFIG=debug
MAKE_HTML=0
OUT_DIR="$REPO_ROOT/coverage"
HTML_DIR="$OUT_DIR/html"
OUT_LCOV="$OUT_DIR/info.lcov"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--release] [--html]

Options:
  --release    Build and test with -c release (default: debug)
  --html       Generate HTML report (genhtml) into ./coverage/html and open it
  -h, --help   Show this help
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release|-r) CONFIG=release ;;
    --html|-H)    MAKE_HTML=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

mkdir -p "$OUT_DIR"

echo "▶ Running tests with coverage (config: $CONFIG)…"
SWIFT_DETERMINISTIC_HASHING=1 swift test -c "$CONFIG" --enable-code-coverage

# Find profdata
PROF=$(find .build -type f -name "default.profdata" -path "*/codecov/*" -print -quit)
if [[ -z "${PROF:-}" ]]; then
  echo "❌ Could not find default.profdata under .build/**/codecov/"
  exit 1
fi
echo "• profdata: $PROF"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Collect test bundles/executables (macOS/Linux)
BUNDLES=()
while IFS= read -r -d '' p; do BUNDLES+=("$p"); done < <(find "$BIN_PATH" -type d -name '*.xctest' -print0 2>/dev/null || true)
if [[ ${#BUNDLES[@]} -eq 0 ]]; then
  while IFS= read -r -d '' p; do BUNDLES+=("$p"); done < <(find "$BIN_PATH" -maxdepth 1 -type f -name '*PackageTests.xctest' -print0 2>/dev/null || true)
fi
if [[ ${#BUNDLES[@]} -eq 0 ]]; then
  echo "❌ No test bundles found under $BIN_PATH"
  exit 1
fi

# Resolve executable paths
BINS=()
for b in "${BUNDLES[@]}"; do
  if [[ -d "$b" && "$OSTYPE" == darwin* ]]; then
    name="$(basename "$b" .xctest)"
    exe="$b/Contents/MacOS/$name"
  else
    if [[ -x "$b" && ! -d "$b" ]]; then
      exe="$b"
    else
      exe="$(find "$b" -type f -perm -111 -print -quit 2>/dev/null || true)"
    fi
  fi
  [[ -n "${exe:-}" && -x "$exe" ]] && BINS+=("$exe")
done
if [[ ${#BINS[@]} -eq 0 ]]; then
  echo "❌ Could not resolve test executables."
  printf '   bundle: %s\n' "${BUNDLES[@]}"
  exit 1
fi

# Choose llvm-cov
LLVM_COV=${LLVM_COV:-llvm-cov}
if [[ "$OSTYPE" == darwin* ]]; then
  LLVM_COV="xcrun $LLVM_COV"
fi
if ! command -v ${LLVM_COV%% *} >/dev/null 2>&1; then
  echo "❌ llvm-cov not found. On macOS, install Xcode CLT; on Linux, install llvm."
  exit 1
fi

# Export LCOV (merge all test executables)
: > "$OUT_LCOV"
for exe in "${BINS[@]}"; do
  echo "• exporting LCOV from: $exe"
  $LLVM_COV export \
    --format=lcov \
    --instr-profile "$PROF" \
    --ignore-filename-regex='/(Tests|\.build)/' \
    "$exe" >> "$OUT_LCOV"
done
echo "✅ LCOV written to $OUT_LCOV"

# Optional HTML into coverage/html
if [[ "$MAKE_HTML" -eq 1 ]]; then
  if ! command -v genhtml >/dev/null 2>&1; then
    echo "❌ genhtml (lcov) not found. Install lcov (e.g. 'brew install lcov')."
    exit 1
  fi
  rm -rf "$HTML_DIR"
  genhtml -o "$HTML_DIR" "$OUT_LCOV" >/dev/null
  echo "✅ HTML report at $HTML_DIR/index.html"
  if [[ "$OSTYPE" == darwin* ]]; then
    open "$HTML_DIR/index.html" || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$HTML_DIR/index.html" || true
  fi
fi

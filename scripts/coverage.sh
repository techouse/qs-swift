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

if [[ "$OSTYPE" == darwin* ]]; then
  # Build tests so we can sign them
  SWIFT_DETERMINISTIC_HASHING=1 swift build -c "$CONFIG" --build-tests --enable-code-coverage

  BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

  # Ad-hoc sign each test bundle executable
  while IFS= read -r -d '' exe; do
    echo "• codesign: $exe"
    /usr/bin/codesign --force -s - "$exe" || true
  done < <(find "$BIN_PATH" -type f -path "*.xctest/Contents/MacOS/*" -print0)

  # Run tests without rebuilding; also silence default.profraw write error
  LLVM_PROFILE_FILE="$OUT_DIR/default-%p.profraw" \
  SWIFT_DETERMINISTIC_HASHING=1 swift test -q -c "$CONFIG" --enable-code-coverage --skip-build
else
  LLVM_PROFILE_FILE="$OUT_DIR/default-%p.profraw" \
  SWIFT_DETERMINISTIC_HASHING=1 swift test -q -c "$CONFIG" --enable-code-coverage
fi

# Find profdata (SwiftPM writes under .build/**/codecov/)
PROF="$(find .build -type f -name "default.profdata" -path "*/codecov/*" -print -quit || true)"
if [[ -z "${PROF:-}" ]]; then
  echo "❌ Could not find default.profdata under .build/**/codecov/"
  exit 1
fi
echo "• profdata: $PROF"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Collect test bundles/executables (macOS & Linux, Swift 5.x–6.x patterns)
BUNDLES=()
# macOS bundles
while IFS= read -r -d '' p; do BUNDLES+=("$p"); done < <(find "$BIN_PATH" -type d -name '*.xctest' -print0 2>/dev/null || true)
# Linux sometimes produces a file named *.xctest (executable, not bundle)
while IFS= read -r -d '' p; do BUNDLES+=("$p"); done < <(find "$BIN_PATH" -maxdepth 1 -type f -name '*Tests.xctest' -print0 2>/dev/null || true)

# If still nothing, scan for any executable whose basename ends with Tests/PackageTests
if [[ ${#BUNDLES[@]} -eq 0 ]]; then
  while IFS= read -r -d '' p; do BUNDLES+=("$p"); done < <(
    find "$BIN_PATH" -maxdepth 1 -type f -perm -111 \( -regex '.*/.*PackageTests$' -o -regex '.*/.*Tests$' \) -print0 2>/dev/null || true
  )
fi

if [[ ${#BUNDLES[@]} -eq 0 ]]; then
  echo "❌ No test bundles/executables found under $BIN_PATH"
  exit 1
fi

# Resolve executable paths
BINS=()
for b in "${BUNDLES[@]}"; do
  exe=""
  if [[ -d "$b" && "$OSTYPE" == darwin* ]]; then
    # macOS .xctest bundle
    name="$(basename "$b" .xctest)"
    exe="$b/Contents/MacOS/$name"
  else
    # Linux, or macOS single-file .xctest
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
  printf '   bundle candidate: %s\n' "${BUNDLES[@]}"
  exit 1
fi

# Robust llvm tool resolver
resolve_llvm_bin() {
  local name="$1"
  # macOS: prefer Xcode toolchain via xcrun
  if [[ "$OSTYPE" == darwin* ]]; then
    if xcrun -f "$name" >/dev/null 2>&1; then
      echo "xcrun $name"; return
    fi
  fi
  # Plain name first
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"; return
  fi
  # Versioned fallbacks (Linux)
  for v in 18 17 16 15 14 13; do
    if command -v "${name}-${v}" >/dev/null 2>&1; then
      command -v "${name}-${v}"; return
    fi
  done
  echo "❌ Could not find ${name}" >&2
  exit 1
}

LLVM_COV="$(resolve_llvm_bin llvm-cov)"

# Export LCOV (merge all test executables)
: > "$OUT_LCOV"
for exe in "${BINS[@]}"; do
  echo "• exporting LCOV from: $exe"
  # Ignore test sources and build dir; keep everything else
  # (tweak the regex if you want to filter generated files or a Bench package)
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
    echo "❌ genhtml (lcov) not found. Install lcov (e.g. 'brew install lcov' or 'apt-get install lcov')."
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

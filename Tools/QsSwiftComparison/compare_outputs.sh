#!/usr/bin/env bash

set -euo pipefail
export SWIFT_DETERMINISTIC_HASHING=1
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"

# Canonicalize query strings by sorting key-value pairs so order differences
# don't cause spurious diffs. This mirrors how we compare semantics, not order.
canonicalize_query() {
  local qs="$1"
  local IFS='&'
  # Split on '&' into an array (bash 3-compatible). Predeclare to avoid
  # "unbound variable" under `set -u` when the input is empty.
  local -a parts=()
  # Only split when the string is non-empty; otherwise leave as empty array.
  if [[ -n "$qs" ]]; then
    read -r -a parts <<< "$qs"
  fi
  # If there are no parts, return an empty string so callers print `Encoded: `
  # without tripping `set -u` on ${parts[@]}.
  if ((${#parts[@]} == 0)); then
    echo ""
    return
  fi
  # Sort pairs lexicographically in a C locale and join back with '&'
  LC_ALL=C printf '%s\n' "${parts[@]}" | sort | paste -sd '&' -
}

# For lines like `Decoded: { ... }`, recursively sort object keys so
# JSON key ordering differences don't cause spurious diffs.
# Uses Node (already a dependency for the comparison).
canonicalize_json_with_node() {
  node - <<'NODE'
let s = "";
process.stdin.on("data", c => (s += c));
process.stdin.on("end", () => {
  function sort(v) {
    if (Array.isArray(v)) return v.map(sort);
    if (v && typeof v === "object") {
      const keys = Object.keys(v).sort();
      const o = {};
      for (const k of keys) o[k] = sort(v[k]);
      return o;
    }
    return v;
  }
  try {
    const v = JSON.parse(s);
    process.stdout.write(JSON.stringify(sort(v)));
  } catch {
    process.stdout.write(s);
  }
});
NODE
}

normalize_stream() {
  local line
  while IFS= read -r line; do
    if [[ "$line" == Encoded:* ]]; then
      local qs="${line#Encoded: }"
      echo "Encoded: $(canonicalize_query "$qs")"
    elif [[ "$line" == Decoded:* ]]; then
      local json="${line#Decoded: }"
      local canon
      canon="$(printf '%s' "$json" | canonicalize_json_with_node)"
      echo "Decoded: $canon"
    else
      echo "$line"
    fi
  done
}

node_output_raw="$(node "$script_dir/js/qs.js")"
swift_output_raw="$(swift run -q -c release QsSwiftComparison)"

# Normalize both outputs to remove ordering noise.
node_output="$(printf '%s\n' "$node_output_raw" | normalize_stream)"
swift_output="$(printf '%s\n' "$swift_output_raw" | normalize_stream)"

if [ "$node_output" == "$swift_output" ]; then
  echo "The outputs are identical."
  exit 0
else
  echo "The outputs are different."
  diff -u <(echo "$node_output") <(echo "$swift_output") || true
  exit 1
fi

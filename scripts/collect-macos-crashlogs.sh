#!/usr/bin/env bash
# Collect recent macOS crash-style logs into a destination folder.
# Usage: collect-macos-crashlogs.sh [DEST_DIR] [MINUTES]
#  - DEST_DIR: output folder (default: crashlogs)
#  - MINUTES : look back this many minutes (default: 60)
#
# This script is intended for CI use on GitHub macOS runners, but also works locally.
set -euxo pipefail

DEST="${1:-crashlogs}"
MINUTES="${2:-60}"

mkdir -p "$DEST"

USER_DR="$HOME/Library/Logs/DiagnosticReports"
SYS_DR="/Library/Logs/DiagnosticReports"

# List directories for debugging context
for dir in "$USER_DR" "$SYS_DR"; do
  if [ -d "$dir" ]; then
    echo "=== Listing $dir ==="
    ls -lah "$dir" || true
  fi
done

# Copy recent crash-like files (multiple common extensions)
for dir in "$USER_DR" "$SYS_DR"; do
  if [ -d "$dir" ]; then
    # Use sudo for system dir on CI; runners allow it.
    CP="cp"
    if [ "$dir" = "$SYS_DR" ]; then CP="sudo cp"; fi

    # -mmin filters by modification time in minutes
    find "$dir" -type f \
      \( -name '*.crash' -o -name '*.ips' -o -name '*.hang' -o -name '*.spin' \) \
      -mmin "-$MINUTES" -print -exec $CP {} "$DEST"/ \; || true
  fi
done

# Include a unified log snippet around the failure window (helpful when no .crash exists)
# Filter for xctest/swift-related messages.
# Ignore errors if log show is unavailable or lacks permission.
if command -v log >/dev/null 2>&1; then
  /usr/bin/log show --style syslog --last "${MINUTES}m" \
    --predicate 'eventMessage CONTAINS[c] "xctest" OR process CONTAINS[c] "xctest" OR process CONTAINS[c] "swift"' \
    > "$DEST/unified-log.txt" 2>/dev/null || true
fi

echo "Collected files in $DEST:"
ls -lah "$DEST" || true

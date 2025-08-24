#!/usr/bin/env bash
# Build DocC sites for both Swift packages (QsSwift and QsObjC) into a GitHub Pages tree.
#
# Usage (CI or local):
#   OUT=docs REPO_NAME=qs-swift bash scripts/docs.sh
#
# Environment variables:
#   OUT        - output directory (default: docs)
#   REPO_NAME  - GitHub repo name used as the base path (default: qs-swift)
#                e.g. pages will live at https://<user>.github.io/${REPO_NAME}/

set -euo pipefail

# Helpful debug trace if DEBUG=1
if [[ ${DEBUG:-0} == 1 ]]; then set -x; fi

ROOT_DIR=$(pwd)
OUT=${OUT:-docs}
REPO_NAME=${REPO_NAME:-qs-swift}

banner() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn()   { printf "\033[33m[warn]\033[0m %s\n" "$*"; }
error()  { printf "\033[31m[err ]\033[0m %s\n" "$*"; }
ok()     { printf "\033[32m[ ok ]\033[0m %s\n" "$*"; }

req() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required tool '$1' not found in PATH"; exit 127
  fi
}

req swift
req xcrun

banner "Toolchain"
swift --version || true
swift package --version || true

banner "Resolving package dependencies"
swift package resolve

# Build one DocC bundle with static hosting settings.
build_docc() {
  local TARGET="$1"   # e.g. QsSwift
  local SUBDIR="$2"   # e.g. qsswift
  local OUTDIR="${OUT}/${SUBDIR}"

  banner "Building documentation: ${TARGET} -> ${OUTDIR}"
  rm -rf "${OUTDIR}"
  mkdir -p "${OUTDIR}"

  # --transform-for-static-hosting ensures relative asset paths; --hosting-base-path
  # points DocC at our GitHub Pages sub-path (user.github.io/${REPO_NAME}/${SUBDIR}).
  # Prefer the non-interactive generator; fall back to preview if unavailable.
  # You can force preview with FORCE_PREVIEW=1 env var.
  if [[ ${FORCE_PREVIEW:-0} != 1 ]] && swift package --disable-sandbox generate-documentation --help >/dev/null 2>&1; then
    # Note: generate-documentation requires explicit write allowance for OUTDIR.
    swift package \
      --disable-sandbox \
      --allow-writing-to-directory "${OUTDIR}" \
      generate-documentation \
      --target "${TARGET}" \
      --output-path "${OUTDIR}" \
      --transform-for-static-hosting \
      --hosting-base-path "${REPO_NAME}/${SUBDIR}"
  else
    warn "Falling back to 'preview-documentation' for ${TARGET} (generator unavailable or FORCE_PREVIEW=1)."
    swift package \
      --disable-sandbox \
      preview-documentation \
      --target "${TARGET}" \
      --output-path "${OUTDIR}" \
      --transform-for-static-hosting \
      --hosting-base-path "${REPO_NAME}/${SUBDIR}"
  fi

  ok "Compilation complete for ${TARGET}; starting DocC conversion (this can take a minute)..."

  # Sanity checks for common assets that must exist for DocC JS to boot.
  if [[ ! -f "${OUTDIR}/index/index.json" ]]; then
    error "Missing ${OUTDIR}/index/index.json (DocC index)."; exit 1
  fi
  # DocC places a per-bundle document under data/documentation/<bundle>.json (bundle ≈ target name lowercased).
  # Some toolchains omit this file, so treat it as a warning only.
  local lower="${SUBDIR}"
  if [[ ! -f "${OUTDIR}/data/documentation/${lower}.json" ]]; then
    warn "Missing ${OUTDIR}/data/documentation/${lower}.json (toolchain-dependent)."
  fi
  if [[ ! -f "${OUTDIR}/theme-settings.json" ]]; then
    warn "Missing ${OUTDIR}/theme-settings.json (expected on some toolchains)."
  fi
  ok "Built ${TARGET} docs"
}

# Build both packages
build_docc "QsSwift" "qsswift"
build_docc "QsObjC"  "qsobjc"

# Prevent GitHub Pages from running Jekyll, which would hide our folders starting with underscores.
banner "Preparing Pages artifacts"
mkdir -p "${OUT}"
touch "${OUT}/.nojekyll"

# Landing page linking to both modules (no auto-redirect).
INDEX_HTML="${OUT}/index.html"
cat >"${INDEX_HTML}" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Qs Documentation</title>
<style>
  :root { color-scheme: light dark; --fg: #111; --bg: #fff; --link:#0366d6; }
  @media (prefers-color-scheme: dark) { :root { --fg:#ddd; --bg:#0b0b0b; --link:#58a6ff; } }
  body { margin: 2rem auto; max-width: 48rem; padding: 0 1rem; font: 16px/1.5 -apple-system, system-ui, Helvetica, Arial, sans-serif; color: var(--fg); background: var(--bg); }
  h1 { font-size: 1.75rem; margin: 0 0 1rem; }
  ul { list-style: none; padding: 0; }
  li { margin: .5rem 0; }
  a { color: var(--link); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .note { margin-top: 1.25rem; font-size: .95rem; opacity: .85; }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
</style>
<h1>Qs Documentation</h1>
<p>Select a module:</p>
<ul>
  <li>• <a href="./qsswift/documentation/qsswift/">QsSwift</a></li>
  <li>• <a href="./qsobjc/documentation/qsobjc/">QsObjC</a></li>
</ul>
<p class="note">Each module is a self-contained DocC site under its own path to keep search/navigation indexes isolated. Built by <code>scripts/docs.sh</code>.</p>
HTML

ok "Wrote ${INDEX_HTML}"

# Back-compat redirect for old links that pointed at /documentation/qsswift/
mkdir -p "${OUT}/documentation"
cat > "${OUT}/documentation/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=../qsswift/documentation/qsswift/">
<title>Redirecting…</title>
<a href="../qsswift/documentation/qsswift/">Redirecting to QsSwift docs…</a>
HTML

# Optional: a simple 404 that links back to landing page
cat >"${OUT}/404.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Not Found</title>
  <style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Helvetica,Arial,sans-serif;padding:3rem;color:#111}</style>
</head>
<body>
  <h1>404 – Not Found</h1>
  <p><a href="./">Back to documentation home</a></p>
</body>
</html>
HTML

# Helpful listing for CI logs
if command -v tree >/dev/null 2>&1; then
  banner "Output tree (${OUT})"
  tree -a "${OUT}" | sed 's/^/    /'
else
  banner "Output listing (${OUT})"
  (cd "${OUT}" && find . -type f | sort | sed 's/^/    /')
fi

banner "Done"

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
  swift package \
    --disable-sandbox \
    preview-documentation \
    --target "${TARGET}" \
    --output-path "${OUTDIR}" \
    --transform-for-static-hosting \
    --hosting-base-path "${REPO_NAME}/${SUBDIR}"

  # Sanity checks for common assets that must exist for DocC JS to boot.
  if [[ ! -f "${OUTDIR}/index/index.json" ]]; then
    error "Missing ${OUTDIR}/index/index.json (DocC index)."; exit 1
  fi
  if [[ ! -f "${OUTDIR}/data/documentation.json" ]]; then
    warn "Missing ${OUTDIR}/data/documentation.json (may be toolchain-dependent)."
  fi
  if [[ ! -f "${OUTDIR}/theme-settings.json" ]]; then
    warn "Missing ${OUTDIR}/theme-settings.json (ok on some toolchains)."
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

# Landing page + redirect to QsSwift by default (can be adjusted)
INDEX_HTML="${OUT}/index.html"
cat >"${INDEX_HTML}" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>qs-swift docs</title>
  <meta http-equiv="refresh" content="0; url=qsswift/documentation/qsswift/" />
  <style>
    html,body{font-family:system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,"Noto Sans",sans-serif;margin:0;padding:2rem;color:#111}
    .container{max-width:800px;margin:0 auto}
    h1{font-size:1.5rem;margin-bottom:1rem}
    ul{line-height:1.9}
    a{color:#0b5fff;text-decoration:none}
    a:hover{text-decoration:underline}
    code{background:#f3f3f5;padding:.1rem .3rem;border-radius:.25rem}
  </style>
  <script>
    // JS fallback if meta refresh is blocked
    (function(){
      var target = 'qsswift/documentation/qsswift/';
      if (location.pathname.endsWith('/')) {
        location.replace(target);
      }
    })();
  </script>
</head>
<body>
  <div class="container">
    <h1>qs-swift documentation</h1>
    <p>You should be redirected automatically. If not, pick a library:</p>
    <ul>
      <li><a href="qsswift/documentation/qsswift/">QsSwift (Swift)</a></li>
      <li><a href="qsobjc/documentation/qsobjc/">QsObjC (Objective‑C)</a></li>
    </ul>
    <p>Build produced by <code>scripts/docs.sh</code>.</p>
  </div>
</body>
</html>
HTML

ok "Wrote ${INDEX_HTML}"

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

#!/usr/bin/env bash
# Browser smoke for the giacenza wasm page (audit finding F-1):
# 1. rebuilds public/ from the candidate sources (`just wasm`) so a
#    stale public/ cannot be tested,
# 2. hashes the freshly built public/app.wasm and exports it,
# 3. the spec asserts, through the browser, that the bytes served at
#    /app.wasm hash to exactly that value — a foreign or stale server
#    cannot pass, and reuseExistingServer is disabled.
# Screenshots + report land in $EVIDENCE_DIR.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/giacenza-browser-evidence}"
mkdir -p "$EVIDENCE_DIR"

# The served artifact must be the candidate's own fresh build.
nix develop --quiet .#wasm -c just wasm
APP_WASM_SHA256=$(sha256sum public/app.wasm | awk '{print $1}')
export APP_WASM_SHA256

nix develop 'github:paolino/dev-assets?dir=playwright' -c playwright test \
    --config scripts/playwright.config.mjs "$@"

echo "browser-smoke: evidence in $EVIDENCE_DIR (app.wasm sha256 $APP_WASM_SHA256)"

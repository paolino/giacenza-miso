# shellcheck shell=bash
set unstable := true

# List available recipes
default:
    @just --list

# Format all Haskell sources
format:
    #!/usr/bin/env bash
    set -euo pipefail
    for i in {1..3}; do
        fourmolu -i src app test
    done

# Check formatting (gate step; no writes)
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fourmolu -m check $(find src app test -name '*.hs')

# Run hlint on domain and test code
hlint:
    #!/usr/bin/env bash
    set -euo pipefail
    hlint src test

# Build native components (library + test suite; the miso app builds in the
# wasm shell, see `just wasm`)
build:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build -O0 lib:giacenza test:unit --enable-tests

# Run unit tests, optionally narrowed by an hspec -m pattern
unit match='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z '{{ match }}' ]]; then
        cabal test unit -O0 --test-show-details=direct
    else
        cabal test unit -O0 --test-show-details=direct \
            --test-option=--match \
            --test-option='{{ match }}'
    fi

# cabal check (Hackage readiness)
cabal-check:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal check

# Full native CI: build, unit, format-check, hlint, cabal-check
ci:
    #!/usr/bin/env bash
    set -euo pipefail
    just build
    just unit
    just format-check
    just hlint
    just cabal-check

# Build the wasm32-wasi miso app into public/ (wasm shell only)
wasm:
    #!/usr/bin/env bash
    set -euo pipefail
    wasm32-wasi-cabal --project-file=cabal-wasm.project update
    wasm32-wasi-cabal --project-file=cabal-wasm.project build
    rm -rf public
    mkdir -p public
    cp -r static/. public/
    wasm_bin=$(wasm32-wasi-cabal --project-file=cabal-wasm.project list-bin giacenza-app)
    node "$(wasm32-wasi-ghc --print-libdir)/post-link.mjs" \
        --input "$wasm_bin" \
        --output public/ghc_wasm_jsffi.js
    cp "$wasm_bin" public/app.wasm
    echo "wasm: public/app.wasm"

# Serve the built wasm page (wasm shell only)
serve:
    #!/usr/bin/env bash
    set -euo pipefail
    cd public
    http-server -p 8080

# Browser smoke test (host with playwright; serves public/ and drives it)
browser-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/browser-smoke.sh

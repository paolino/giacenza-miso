# giacenza-miso

Giacenza average-balance calculator prototype in miso (Haskell MVU),
compiled to GHC wasm32-wasi — evaluating miso against the
PureScript/Halogen and Reflex/jsaddle-wasm paths.

Choose one or more bank-movement CSV files (or paste a CSV), confirm
the date column, amount column and number format per statement, and
read a per-year table of *saldo* (31 Dec balance) and *giacenza*
(average daily balance). Final report sums the analysed statements.

## Develop

Enter the native shell (GHC, cabal, just, fourmolu, hlint):

```sh
nix develop
```

Run the unit proofs (native GHC):

```sh
just unit
```

Format and lint:

```sh
just format
just hlint
```

Full native CI (build + unit + format-check + hlint + cabal-check):

```sh
just ci
```

## Build the wasm page

Enter the miso wasm shell (GHC 9.14 wasm32-wasi toolchain from
miso's flake) and build the static page into `public/`:

```sh
nix develop .#wasm
just wasm
```

Serve it:

```sh
just serve   # http://localhost:8080
```

The page is static: `public/` holds `index.html`, `index.js`
(WASI shim), `ghc_wasm_jsffi.js` and `app.wasm`.

Browser smoke (real Chromium via Playwright; builds nothing, needs
`public/app.wasm` to exist):

```sh
EVIDENCE_DIR=/tmp/shots just browser-smoke
```

Covers INV-1-CONST (paste + compute → table 2023, 100.00, 100.00),
INV-1-ERROR-DATE, INV-1-ERROR-EMPTY, and CSV file upload; screenshots
land in `$EVIDENCE_DIR`.

## Wasm devloop notes (evaluated 2026-08-31, GHC 9.14.1.20260330
via miso's flake `devShells.wasm` / ghc-wasm-meta `all_9_14`)

- Clean wasm build (`nix develop .#wasm -c just wasm`, cold:
  toolchain realisation + `wasm32-wasi-cabal update` + miso and
  dependencies from source + app): **213 s wall**. Warm incremental
  rebuild of the app only: **~6 s**.
- Error quality: good. A deliberate wrong property name surfaces
  `Not in scope: ‘P.style_’ … Perhaps use one of these:
  ‘H.style_’ … ‘P.type_’` with the offending line — typed
  suggestions, no wall of type noise. Type mismatches across the
  Text/MisoString boundary print both types verbatim.
- `repl-watch`: `ghciwatch` 1.1.5 and the interactive flag are
  present in the wasm shell, but the browser-backed ghci repl needs
  an interactive shell (nix develop shellHook) and a live browser
  tab; not evaluated in this headless run — operator follow-up.

## Layout

- `src/Giacenza/Types.hs` — shared money/date/result vocabulary
- `src/Giacenza/Parse.hs` — CSV text → headers, rows, movements
- `src/Giacenza/Compute.hs` — movements → per-year saldo/giacenza
- `app/Main.hs` — miso MVU page
- `test/` — native Hspec/QuickCheck proofs of the spec invariants
- `static/` — `index.html` + WASI shim loader

Domain semantics follow `lambdasistemi/giacenza` (read-only
reference): movements apply in CSV row order, sparse movements carry
through gaps, days after the last movement fill through 31 Dec, and
the giacenza divisor is the calendar year length.

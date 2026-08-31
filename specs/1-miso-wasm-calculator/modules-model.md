# Modules model — issue #1

New modules only. No bodies, imports, or algorithms.
Upstream = dependency-graph owner, not a Git remote.

## M-TYPES — `src/Giacenza/Types.hs`

Owns: `Value`, `Year`, `Saldo`, `Giacenza`, `Movement`,
`NumberFormat`, `Config`, `Result`, `ParseError`.
Depends on: none of the modules below.
Promoted: these types are the shared language. Do not fork a
second money/date vocabulary in the UI.

## M-PARSE — `src/Giacenza/Parse.hs`

Owns: CSV text → headers + rows; header-name lookup; date field;
amount field under a `NumberFormat`.
Depends on: M-TYPES.
Does not own: daily expansion or year aggregation.

## M-COMPUTE — `src/Giacenza/Compute.hs`

Owns: movements → per-year `(Saldo, Giacenza)` with production
`foldDays` / year-end fill / leap divisor semantics.
Depends on: M-TYPES.
Does not own: CSV or DOM.

## M-APP — `app/Main.hs`

Owns: miso model, actions, view, `main` / `hs_start` export.
Depends on: M-TYPES, M-PARSE, M-COMPUTE.
Does not own: a second parser or a second average-balance formula.

## M-TEST — `test/`

Owns: native Hspec + QuickCheck proofs of the spec invariants.
Depends on: M-TYPES, M-PARSE, M-COMPUTE.
Does not own: production modules.

## M-BUILD — flake / cabal / just / static wasm page

Owns: native and `.#wasm` shells, just recipes, `index.html` WASI
shim, package metadata.
Depends on: M-APP as the wasm executable.
Forbidden: `cassava`, `streaming`, `attoparsec`; editing the two
reference repositories.

## Direction

```
M-BUILD → M-APP → M-PARSE → M-TYPES
                 → M-COMPUTE → M-TYPES
M-TEST  → M-PARSE, M-COMPUTE, M-TYPES
```

No reverse edge from domain modules into M-APP.

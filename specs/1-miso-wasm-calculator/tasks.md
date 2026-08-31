# Tasks — issue #1 / slice S1

- [x] T001 Scaffold flake (native + `.#wasm` miso shell), cabal
      package, fourmolu.yaml, justfile, `.gitignore` extras
- [x] T002 M-TYPES
- [x] T003 M-PARSE + RED/GREEN proofs for parse/error invariants
- [x] T004 M-COMPUTE + RED/GREEN proofs for compute invariants
- [x] T005 M-APP miso UI (textarea, columns, format, table, error)
- [x] T006 Wasm page (`hs_start`, static index, WASI shim) via
      `just wasm`
- [x] T007 Browser evidence: Playwright `just browser-smoke` or
      screenshot + description for INV-1-CONST and
      INV-1-ERROR-DATE
- [x] T008 README: how to `just unit`, `just wasm`, serve the
      page; PR body includes FR-010 devloop notes

Slice S1 closes when T001–T008 are checked and the auditor has
reported on the candidate.

# Tasks — issue #1 / slice S1

- [ ] T001 Scaffold flake (native + `.#wasm` miso shell), cabal
      package, fourmolu.yaml, justfile, `.gitignore` extras
- [ ] T002 M-TYPES
- [ ] T003 M-PARSE + RED/GREEN proofs for parse/error invariants
- [ ] T004 M-COMPUTE + RED/GREEN proofs for compute invariants
- [ ] T005 M-APP miso UI (textarea, columns, format, table, error)
- [ ] T006 Wasm page (`hs_start`, static index, WASI shim) via
      `just wasm`
- [ ] T007 Browser evidence: Playwright `just browser-smoke` or
      screenshot + description for INV-1-CONST and
      INV-1-ERROR-DATE
- [ ] T008 README: how to `just unit`, `just wasm`, serve the
      page; PR body includes FR-010 devloop notes

Slice S1 closes when T001–T008 are checked and the auditor has
reported on the candidate.

# Spec — giacenza miso wasm32-wasi prototype (issue #1)

**Input:** https://github.com/paolino/giacenza-miso/issues/1
**Ceilings:** this file ≤ 180 lines. Record: bytes/lines after freeze.

## Paramount user story

A person pastes a bank-movement CSV into a browser page, confirms
the date column, amount column, and number format, and sees a
per-year table of *saldo* (31 Dec balance) and *giacenza* (average
daily balance). A bad paste or bad column shows a visible error
instead of a silent wrong table or a crash.

## Why this ticket exists

The page is a vehicle for evaluating **miso compiled with GHC
`wasm32-wasi`**: build time, error quality, and whether
`repl-watch` hot-reload works. The evaluation belongs in the PR
body. The calculator must still be correct.

Canonical domain: `lambdasistemi/giacenza` `src/Compute.hs` +
`src/Types.hs` (read-only). UI shape: `paolino/giacenza-browser`
(read-only). Do not edit those repositories.

## Functional requirements

- FR-001: CSV arrives only through a pasted-text area. No file
  picker, drag-drop, or multi-file list.
- FR-002: First non-empty line is the header. Fields split on
  comma or semicolon; quoted fields follow the giacenza-browser
  splitter (quotes toggle; comma/semicolon inside quotes are
  data). Header names are trimmed.
- FR-003: After paste, the date-column and amount-column controls
  are filled from those headers. Number format is European
  (`1.234,56`) or American (`1,234.56`); European is the default.
- FR-004: Dates are `YYYY-MM-DD`. Amounts parse as production
  `parseValue` (see data-model). Missing column, unparseable date,
  or unparseable amount is a visible error; the result table is
  not shown.
- FR-005: Movements are applied in CSV row order (Haskell
  `foldDays`, not the PureScript sort). Sparse movements expand to
  a dense daily balance: carry the running balance through gaps;
  after the last movement, fill through 31 Dec of that movement's
  year. Days *before* the first movement of a year are omitted,
  not treated as zero.
- FR-006: For each year that has a 31 Dec balance, *saldo* is that
  balance and *giacenza* is (sum of emitted daily balances) /
  (365, or 366 if leap). The divisor is the calendar year length,
  not the number of emitted days.
- FR-007: The result table lists year, giacenza, saldo. Amounts
  display with two decimal places (`showFFloat (Just 2)`).
- FR-008: Header-only CSV (headers, no data rows) shows an empty
  result, not an error. Empty paste shows a visible error.
- FR-009: The page is a wasm32-wasi miso app served as static
  files. Native GHC tests cover FR-004–FR-008; the wasm binary is
  a separate artifact.
- FR-010: The PR body records the wasm devloop: wall time of a
  clean wasm build, quality of a deliberate compile error, and
  whether `repl-watch` was tried and whether it reloaded.

## Invariants

Severity: BLOCKING = wrong money figure or silent failure.
ADVISORY = eval/UX.

- INV-1-CONST (BLOCKING): American CSV `date,amount` / `2023-01-01,100`
  → year 2023, saldo 100, giacenza 100.
- INV-1-EURO (BLOCKING): European amount `1.234,56` on 2023-01-01
  → saldo 1234.56, giacenza 1234.56. Negative `-1.234,56` negates.
- INV-1-AMER (BLOCKING): American amount `1,234.56` on 2023-01-01
  → saldo 1234.56, giacenza 1234.56.
- INV-1-GAP (BLOCKING): 2024 (leap) `2024-01-01,1000` then
  `2024-06-01,-200` → saldo 800, giacenza `(152*1000+214*800)/366`.
- INV-1-PARTIAL-YEAR (BLOCKING): only `2023-06-01,50` → saldo 50,
  giacenza `(214*50)/365`. Days before 1 Jun are omitted.
- INV-1-YEAR-CROSS (BLOCKING): `2023-12-31,10` then `2024-01-01,5`
  → 2023 saldo 10, giacenza `10/365`; 2024 saldo 15, giacenza 15.
- INV-1-EMPTY-ROWS (BLOCKING): headers only → empty table, no error.
- INV-1-ERROR-DATE (BLOCKING): bad date or missing column name →
  visible error text; no saldo/giacenza numbers from that paste.
- INV-1-ERROR-EMPTY (BLOCKING): empty paste → visible error.
- INV-1-WASM (BLOCKING): `nix develop .#wasm` builds a `.wasm`.
- INV-1-BROWSER (BLOCKING): in a real browser, paste+configure+
  compute shows INV-1-CONST numbers; a bad date shows an error.
- INV-1-DEVLOOP (ADVISORY): PR body contains the three FR-010
  observations.

## Success criteria

- Native tests fail if any BLOCKING compute/parse invariant is
  violated, and have been shown red on a mutant of that oracle.
- A wasm32-wasi binary exists from the miso `wasm` devShell.
- Browser evidence (Playwright run or screenshot plus description)
  shows INV-1-CONST and INV-1-ERROR-DATE.
- PR opened into `main`, left unmerged.

## Non-goals

- Multi-file upload, drag-drop, propagate-config, theme toggle.
- `cassava`, `streaming`, `attoparsec`, production `Compute.hs`.
- Production deploy, GitHub Pages, JS-backend fallback.
- Editing `lambdasistemi/giacenza` or `paolino/giacenza-browser`.
- Merging the PR.

## Assumptions

- Header delimiter is comma or semicolon, not tab.
- Production `parseValue` cents are `decimal / 100` after the
  decimal separator (`1,5` European = 1.05). Match that.
- No sort step. Unsorted dates follow Haskell `foldDays`.

# Plan — giacenza miso wasm32-wasi prototype

**Ceilings:** this file ≤ 160 lines. No algorithms.

## Status

- Completed: mandate authoring (this tree).
- Current: freeze gate, draft PR, dispatch OWNER.
- Blockers: none at plan time. GLM launch depends on `pi` on PATH
  (`glm` wrapper). If `glm --approve` cannot start, T.O. files Q-001
  rather than substituting a family.

## Technical strategy

Greenfield Haskell app in this repo. One bisect-safe slice: the
whole prototype. Topology: **OWNER** (wasm + live browser + domain
semantics are not a complete LIGHT gate; no approved sandbox
launcher is named).

Pin **miso's flake** `devShells.wasm` (`ghc-wasm-meta` `all_9_14` +
`haskell-miso-cachix`), not a hand-rolled `all_9_12` shell. Follow
`haskell-miso/miso-sampler`: `wasm32-wasi-cabal`, reactor export
`hs_start`, static `index.html` + `@bjorn3/browser_wasi_shim`.

Native GHC (default `devShell`) owns tests. Wasm shell owns the
browser binary. Do not run Hspec under wasm.

Domain: reimplement production `foldDays` / `saldos` / `giacenzas`
/ `parseValue` with `base` + `containers` + `time` + `text`.
Forbidden deps: `cassava`, `streaming`, `attoparsec`.

UI: one miso MVU component. Paste textarea, header-derived column
selects, European/American format, compute action, result table,
error node. Cite giacenza-browser layout; do not copy Halogen.

## Constraints

- House Haskell: fourmolu (`column-limit: 70`, leading commas/
  arrows, `haddock-style: multi-line`), `-O0` in just recipes,
  `cabal check` clean, Haddock on exports, module headers.
- `just` recipes wrap cabal/nix. CI recipe mirrors local gate
  minus the wasm build if wasm is too heavy for every native
  `just ci`; the **slice gate still requires wasm**.
- Flake `nixConfig` extra-substituters: `haskell-miso-cachix`.
- `draft=NONE`. Commit owner: `glm --approve` (`harness=pi
  provider=zai model=glm-5.3-flash effort=max`). Auditor:
  `claude --dangerously-skip-permissions --model 'claude-opus-5[1m]'`.
- T.O. is grok (parent dispatch). One grok seat: auditor is not grok.
- No push by the commit owner. T.O. pushes accepted SHA and
  opens/updates the PR. Do not merge.
- Do not edit `/code/giacenza` or `/code/giacenza-browser`.

## Live boundary

The unit suite cannot see: wasm instantiation, JSFFI textarea
events, browser DOM. Per live-boundary-smoke:

- Gate includes wasm artifact existence (loud fail if missing).
- Browser proof is a named follow-up on the same slice: Playwright
  `just browser-smoke` **if** it fits the flake; otherwise a
  screenshot plus a short description in the PR, covering
  INV-1-CONST and INV-1-ERROR-DATE. T.O. will not mark the PR
  ready until that artifact exists.

## Slices

| ID | Mode | Outcome |
|----|------|---------|
| S1 | OWNER | App + tests + wasm page + PR body devloop notes |

Pre-slice base: HEAD after the planning commits on
`prototype/miso-wasm-calculator`.

## Verification commands (named, not implemented here)

- Focused RED/GREEN: `nix develop --quiet -c just unit`
- Format: `nix develop --quiet -c just format-check`
- Full native: `nix develop --quiet -c just ci`
- Wasm: `nix develop --quiet .#wasm -c just wasm`
- Optional: `just browser-smoke`

## Build budget

`builds_budget=8` (auditor-spent). Wasm compiles are the scarce
item; native `-O0` tests are free readiness.

## Residuals expected

- GitHub Actions on this PR will not run until a workflow exists
  on `main` (Actions pull_request rule). Out of slice: do not
  bootstrap org CI on `main`.
- Theme toggle, file upload: out of slice.

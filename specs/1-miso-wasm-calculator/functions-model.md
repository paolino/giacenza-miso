# Functions model — issue #1

Signatures and argument names only. No bodies.

## M-PARSE

- `parseCsv :: csvText -> Either ParseError CsvTable`
- `parseDate :: raw -> Either ParseError Day`
- `parseAmount :: numberFormat -> raw -> Either ParseError Value`
- `extractMovements :: config -> csvTable -> Either ParseError [Movement]`

`extractMovements` fails on missing `dateColumn` / `amountColumn`,
on any row with a bad date, and on any row with a bad amount.

## M-COMPUTE

- `yearResults :: movements -> Result`

`movements` are already in apply order. `yearResults` is the
production `foldDays` then 31 Dec saldo and leap-aware giacenza.

## M-APP

- `initialModel :: Model`
- `updateModel :: action -> Effect context props Model action`
- `viewModel :: context -> props -> Model -> View context action`
- `main :: IO ()`

Wasm builds export `main` to JavaScript as `hs_start`.

Actions (names): `CsvInputChanged`, `DateColumnChanged`,
`AmountColumnChanged`, `NumberFormatChanged`, `ComputeRequested`.

## M-TEST (proof names the owner must provide)

- `prop_inv1_const`
- `prop_inv1_euro`
- `prop_inv1_amer`
- `prop_inv1_gap`
- `prop_inv1_partial_year`
- `prop_inv1_year_cross`
- `prop_inv1_empty_rows`
- `prop_inv1_error_date`
- `prop_inv1_error_empty`

Each proof must have a demonstrated red mutant before it ships
green (commit-owner RED bundle).

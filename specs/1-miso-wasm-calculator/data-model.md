# Data model — issue #1

Fields, relationships, validation. No parsers-as-code.

## D-VALUE

Monetary amount. Signed. Internal representation is unrestricted
fractional (production uses `Double`). Display is two decimal
places.

## D-YEAR

Gregorian calendar year. Leap iff divisible by 4 but not 100,
unless divisible by 400.

## D-MOVEMENT

- `date`: calendar day, `YYYY-MM-DD` only.
- `amount`: D-VALUE delta applied on `date` (not a running
  balance).

Order: CSV row order is the apply order.

## D-NUMBER-FORMAT

- `European`: decimal `,`, thousands `.`
- `American`: decimal `.`, thousands `,`

Validation (production `parseValue`): optional leading `-`;
integer groups joined by the thousands separator (each group
after the first is `*1000 + n`); optional decimal separator then
an integer `c` contributing `c/100`. No thousands grouping
required. Space-stripped groups are allowed.

## D-CONFIG

- `numberFormat`: D-NUMBER-FORMAT (default European)
- `dateColumn`: header name, exact match after trim
- `amountColumn`: header name, exact match after trim

Both names must occur in the parsed header list.

## D-CSV-TABLE

- `headers`: ordered unique-enough names (duplicates: first match
  wins)
- `rows`: ordered field lists, same delimiter as the header line

Empty input is not a table. Header-only is a table with no rows.

## D-RESULT

Map from D-YEAR to `(saldo, giacenza)` for years that have a
31 Dec emitted balance. Missing years are absent, not zero.

- `saldo`: emitted balance on 31 Dec.
- `giacenza`: sum of emitted daily balances in that year divided
  by 365 or 366.

Days before the first movement of the whole series are not
emitted.

## D-ERROR

Human-readable. Must name the cause class: empty input, missing
column, invalid date, invalid amount. Must not present a
D-RESULT for the same submit.

## D-MODEL (UI)

- pasted text
- detected headers
- D-CONFIG in progress
- either D-RESULT, D-ERROR, or idle

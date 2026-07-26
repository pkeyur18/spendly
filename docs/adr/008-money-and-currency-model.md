# ADR-008: Integer-minor-units `Money`, single hardcoded currency (INR) for v1

## Status

Accepted; multi-currency explicitly deferred, not rejected.

## Context

Financial amounts must never be subject to binary floating-point rounding error, and the app
needs a currency to display and format amounts in. At v1, Spendly targets a single-currency
personal-finance use case.

## Decision

Store and compute all amounts as integers in the currency's smallest unit
(`amountMinor: int` in the `Expenses`/`Budgets` tables, `Money.minor: int` in
`lib/core/money/money.dart`) — never a `double`, in storage or arithmetic. `Money.parse`
parses decimal input strings digit-by-digit rather than through `double.parse`, specifically
to avoid binary floating-point rounding, with explicit round-half-up handling at the 3rd
decimal place. A `major` `double` getter exists only for display formatting and is documented
"never for math." Currency is hardcoded to INR (`₹`, `en_IN` locale formatting via
`NumberFormat.simpleCurrency`) — there is no currency-code column anywhere in the schema, so
every amount in the database is implicitly the same single currency.

## Alternatives Considered

- **`double`/float amounts** — rejected outright: standard floating-point rounding error is
  unacceptable for money, full stop.
- **A dedicated arbitrary-precision decimal package (e.g. `decimal`)** — considered, but
  integer minor-units is simpler, faster, and sufficient given amounts are bounded (personal
  expense values) and all arithmetic is addition/subtraction of already-rounded amounts, not
  operations that need arbitrary decimal precision.
- **Multi-currency from day one (currency-code column, per-transaction currency, conversion
  handling)** — explicitly deferred, not rejected: flagged in source with a `ponytail:`
  comment as a known v2 candidate ("swap to a settings-driven currency code when
  multi-currency lands"). Building it now would require deciding conversion-rate sourcing,
  historical-rate-at-transaction-time semantics, and cross-currency reporting/aggregation —
  real design work with no current user need driving it.

## Consequences

- Money arithmetic throughout the app is exact integer arithmetic — no class of
  floating-point rounding bugs is possible.
- Any future multi-currency work is a real schema migration (add a currency-code column,
  backfill existing rows as INR, revisit every aggregate query that currently assumes a
  single currency) — not a small change. This should be planned as its own design exercise
  when it becomes a real requirement, not bolted on incrementally.

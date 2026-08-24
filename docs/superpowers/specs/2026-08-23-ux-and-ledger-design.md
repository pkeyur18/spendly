# UX Enhancements & Account Ledger — Design Spec

Date: 2026-08-23
Status: Presented to user, pending approval before implementation.

## Problem

Spendly answers "where did my money go" well. It does not answer the two
questions a budget-disciplined saver actually asks day to day:

1. **"Am I on track right now?"** The hero card shows a month total and a
   percentage of budget. On day 12 of 30, "61% of budget" is an emergency; on
   day 25 it is a win. The card renders both identically.
2. **"What do I actually have?"** There is no income, no balance, no savings
   rate. The app records outflow and nothing else.

Alongside those, several daily-loop actions carry avoidable friction, and two
features are half-built in the repo (recurring expenses, payment methods).

## Current state (verified against code, not docs)

Docs are stale in two ways worth recording:

- **Drift schema is v9**, not v7 (`lib/core/db/database.dart:181`). FX
  spending and trip date-range auto-tagging shipped without a README/PROGRESS
  entry.
- Test count and feature list in README predate those two features.

Confirmed gaps:

| Gap | Evidence |
|---|---|
| Recurring expenses are dead code | `Expenses.isRecurring` / `Expenses.recurrence` columns exist; `lib/features/expenses/recurrence.dart` date math exists and is tested (`test/recurrence_test.dart`); nothing writes the columns and no reminder is ever scheduled |
| No transaction search | Only "Search categories" inside the filter sheet (`all_transactions_screen.dart:424`) |
| No forward-looking pace | `dailyAverage` exists but only backward-looking in reports (`report_model.dart:112`) |
| No undo on delete | Delete is guarded by a "This can't be undone" dialog (`expense_tile.dart:117`) — friction on the common path, no recovery on the rare one |
| Bottom nav pushes routes | `home_screen.dart:329-369` — every tab is `Navigator.push`; back-stack grows, scroll position lost, two items are `coming soon` snackbars |
| `paymentMethod` is inert | Free-text column, written and exported to Excel, never analyzed or offered as a breakdown |
| No income / balances | Zero `income` hits in `lib/` |

## Architectural decision: separate ledger table, not a `kind` column

The obvious move for adding income and transfers is a `kind`
(`expense`/`income`/`transfer`) column on the existing `Expenses` table, so
one table holds all money movement. **Rejected.**

Counting real call sites: income and transfer rows must be **excluded** from
roughly fourteen existing queries — `monthTotal`, `totalInRange`,
`totalsByCategory`, `watchTotalsByCategory`, `listInRange`, `watchInRange`,
`watchLifetimeStats`, `earliestExpenseDate`, `distinctCategoryIdsInRange`,
`watchByTag`, `watchCountByTag`, `watchTotalsByTag` (all
`expense_repository.dart`), plus `tag_repository.dart:149-164` and
`category_repository.dart:62-65` — and **included** in about three new ones.

A `kind` column makes inclusion the default and requires fourteen opt-out
patches at scattered call sites. A single missed guard silently inflates
reported spending, corrupts budget math, and misfires threshold
notifications — with no visible error. That is precisely the failure shape
`docs/known-issues.md` push-back #1 documents as having hit this repo three
times independently.

**Decision:** income and transfers live in a new `LedgerEntries` table.
`Expenses` stays expense-only and gains exactly one additive nullable column
(`accountId`). Exclusion becomes structural rather than remembered; no
existing query changes; budgets, donut, trend, reports, recap, widgets, and
lifetime stats are untouched by construction.

**Accepted cost:** balance math reads two tables, and any view wanting a
combined timeline performs a union. That union is confined to one new screen
(account detail). All Transactions stays expense-only.

**Rejected alternative:** accounts without income (balances that only ever
decrease). Cheaper, but cannot answer "did I save anything", which is the
reason accounts were requested.

## Phase plan

Each phase ships independently usable behavior, with tests, `flutter analyze`
clean, and a PROGRESS.md entry. Phases are ordered by value ÷ effort.

### Phase 1 — Daily-loop friction (no schema change)

1. **Pace-aware hero card.** Derive elapsed-vs-remaining days for the current
   month and add one line to the hero: remaining-per-day allowance and an
   on-track / over-pace signal. Pure function in `dashboard_providers.dart`
   style, unit-tested (month boundaries, zero budget, over budget, first day,
   last day). UI change confined to `_HeroCard` (`home_screen.dart:169-274`).
   Colour is never the only signal — the text states the status (accessibility
   commitment in PRODUCT.md).
2. **Undo on delete.** Remove the confirm dialog; delete optimistically and
   show a 5-second undo snackbar that re-inserts the row. Fewer taps on the
   common path *and* genuinely reversible. Re-insert restores the same
   `externalId` so backup Merge identity survives.
3. **Duplicate a transaction.** Long-press a transaction → "Add again", opens
   Quick Add prefilled with today's date. Covers the daily-coffee case without
   touching recurring logic.
4. **Transaction search.** One text field over All Transactions matching note
   text, category name, and amount. New repository query + provider; reuses
   the existing lazy-paging list.
5. **Real tabs.** Replace push-per-tab with an `IndexedStack` shell so the
   back-stack stops growing and scroll position survives tab switches. Removes
   the two `coming soon` snackbars, which are visible unfinished edges ahead
   of store submission.

### Phase 2 — Recurring expenses (schema v10)

Finishes FR-7 using infrastructure already present: the columns, the tested
date math, and `NotificationService`.

1. Quick Add gains a repeat toggle + frequency picker (daily/weekly/monthly),
   writing the existing `isRecurring` / `recurrence` columns.
2. **Schema v10:** one nullable `nextDueDate` column on `Expenses`. Needed
   because `recurrence.dart` computes the next occurrence from a date but
   nothing records which occurrence was last confirmed. Nullable with no
   default, so `ADD COLUMN` is safe on a populated table and existing rows need
   no backfill.
3. Due-date reminder scheduled through the existing notification service;
   tapping it opens a prefilled Quick Add to **confirm** — never a silent
   auto-log, per the locked PRD decision (PROGRESS.md, PRD Q3).
4. An "Upcoming" list to view and cancel recurring items.

Per `database.dart:174-181`, `test/migration_test.dart` gets a seeded row
exercising the new migration block before this phase merges.

### Phase 3 — Receipt photos (schema v11)

Attach a photo to an expense using `image_picker` (already a dependency) and
the storage-and-restore path the profile avatar already proves
(`backup_repository_test.dart` fakes `getApplicationSupportPath()` for exactly
this). One nullable column; backup payload carries it the way the avatar
already does.

### Phase 4 — Accounts (schema v12, backup v4)

1. `Accounts` table: name, type (cash/bank/card/wallet), opening balance,
   archived flag, `externalId`.
2. `Expenses.accountId` — nullable, additive, no existing query changes.
3. One-time migration of distinct `paymentMethod` strings into real accounts,
   preserving the original text on rows it cannot match.
4. Account picker in Quick Add; per-account spend breakdown.
5. Backup format v4 carries accounts. Restore must still read v3 and below
   (`backup_format.dart` already rejects only *newer* versions).

Ships value on its own, before any income exists.

### Phase 5 — Income & savings rate (schema v13, backup v4 extended)

1. `LedgerEntries` table: kind (income/transfer), amount, date, account,
   optional counter-account, note, source label, `externalId`.
2. Income entry UI.
3. Net cashflow and savings rate surfaced in Monthly Recap and reports — the
   recap headline becomes "you kept 22% this month" rather than "you spent
   ₹42,000".
4. Backup carries ledger entries; Merge matches on `externalId` like every
   other table.

**Assumption, stated explicitly since it was left open:** budgets stay
strictly expense-based. Income-aware budgeting ("budget = 70% of what came
in") is deliberately not in scope — it changes budget semantics for every
existing user and earns its own decision later.

### Phase 6 — Transfers & live balances

1. Transfer entries (account → account), excluded from both spend and income
   totals.
2. Derived balance: opening + income − expenses ± transfers. Never stored —
   derivation only, matching the app's existing preference for computed over
   persisted state.
3. Account detail screen: the one place expenses and ledger entries are unioned
   into a single timeline.
4. Balance summary on the dashboard.

### Phase 7 — Insight, goals, security

1. **Insight feed** — "Food is up 40% vs your 3-month average",
   "₹3,200/month in subscriptions". Pure derived math, no schema. Sequenced
   last because it needs Phase 2's recurring data and real history to be worth
   reading.
2. **Savings goals** — meaningful only once income exists (Phase 5).
3. **App lock** — biometric/PIN via `local_auth`. The only new dependency in
   this entire plan; PROGRESS.md's dependency-pinning constraints must be
   re-checked before adding it.
4. **Note/merchant autocomplete** — local frequency ranking over past notes.
   Entry gets faster the longer the app is used.

## Constraints honored

- **Offline absolute.** No phase adds a network dependency. `local_auth`
  (Phase 7) is device-local.
- **Money stays integer minor units** everywhere, including balances and
  ledger entries.
- **Never destroy data silently.** Accounts archive rather than delete, like
  categories and tags. Undo-on-delete strictly increases recoverability.
- **Backup fidelity is the correctness bar.** Every new table carries an
  `externalId` for Merge matching; every format bump keeps older backups
  readable.

## Testing strategy

Follows the existing convention (37 test files, pure-logic-first):

- Pure functions get direct unit tests: pace math, balance derivation,
  savings rate, recurring due-date advancement, `paymentMethod` → account
  migration mapping.
- Every schema bump extends `test/migration_test.dart` with a seeded row
  exercising the new block, per the standing warning at `database.dart:174-181`
  (that class of migration bug has shipped three times).
- Every backup format bump extends `backup_repository_test.dart` with a
  round-trip plus an older-version restore.
- Widget tests avoid `pumpAndSettle` — Drift streams and fl_chart never settle;
  providers are exercised through `ProviderContainer`.

## Out of scope

- Income-aware budgeting (see Phase 5 assumption).
- Multi-currency generalization beyond the existing trip-FX feature.
- Cloud sync in any form (ADR-004).
- Bank/SMS import.

# Budget Recommendation — Design Spec

Date: 2026-08-23
Status: Approved by user, pending final spec review before implementation plan.

## Problem

User wants the app to recommend next month's budget (overall + per-category),
learned from their own last 6 months of spend. Recommendation must be
tap-to-apply, still manually editable, and stay current as new expenses land
("actively updated").

## Architectural decision (the pushback)

"Actively updated" does **not** require a persisted recommendation or a
background job. This app has no background-execution mechanism by design
(`local_auto_backup.dart:24-32` — workmanager/android_alarm_manager_plus
rejected as heavy/flaky for this project) and no ADR endorses adding one.
The existing pattern for "needs to reflect current state" is a Riverpod
provider recomputing live off a Drift stream (`trendProvider`) or an
app-open/resume check (`monthlyRecapCheckProvider`, `autoBackupCheckProvider`).

Recommendation is computed on demand, pure Dart, no persistence, no ML/network
dependency (none exist in `pubspec.yaml`, none permitted per
`docs/adr/004-no-cloud-sync.md` and `PRODUCT.md` offline-first principle).
Only genuinely new piece of infrastructure: one aggregation query.

Budgets are single-currency (`amountMinor`, INR-only per PRODUCT.md principle
#2), so there is no FX-conversion problem in the pattern math. Trip expenses
are structurally identifiable via `Expenses.tagId → Tags.tripStartDate != null`
— excluding them is a plain filter, no schema change.

## Algorithm

Pure function, no ML, no external deps.

1. **Window**: last 6 *completed* calendar months before the target month.
   Current in-progress month excluded (partial data skews the average).
2. **Per category, per month**: total home-currency spend, trip-tagged
   expenses excluded (`Tags.tripStartDate IS NOT NULL`). A month with no
   matching expenses counts as a real `0`, not "missing."
3. **Category eligibility**: skip a category entirely if it is archived,
   `isIgnoredForBudget`, or has zero spend history across the whole window.
4. **Outlier guard**: if the category has ≥4 months of data in the window,
   drop the single month whose total exceeds 1.75× the median of the window
   (drop at most one, non-iterative). Prevents one unusual non-trip spike
   from dragging the recommendation up.
5. **Weighted average**: linear recency weights (oldest month = 1, ...,
   newest = N after any drop); weighted average = Σ(total_i × weight_i) /
   Σ(weight_i).
6. **Rounding**: round to nearest ₹50 for a clean, displayable number.
7. **Overall recommendation** = sum of per-category recommendations across
   eligible (non-ignored) categories — mirrors existing
   `effectiveOverallBudget` semantics rather than being computed
   independently from raw totals.
8. **Confidence**: if fewer than 6 months of data are available (new
   user/category), still recommend, labelled with the month count used
   (e.g. "based on 3 months").

## Data flow / new components

No new Drift table, no schema migration.

- `expense_repository.dart`: new query returning per-category monthly totals
  for the last N completed months, trip-tagged rows excluded (join `Tags`,
  filter `tripStartDate IS NULL`). Analogous in shape to existing
  `watchLastNMonths` / `totalsByCategory`.
- New pure function module (same pattern as `report_model.dart`): takes the
  monthly totals, returns `{Map<categoryId, Money> perCategory, Money
  overall, Map<categoryId, int> monthsUsed}`.
- New Riverpod provider, family-keyed by target `monthKey`, composing the
  query stream + pure function — lives alongside existing budget providers in
  `budget_repository.dart`.

## UI

- **Inline**: on `BudgetSetupScreen`, only when viewing **next month**, for
  any category/overall card that has no budget set yet for that month — show
  "Suggested ₹X" (and "based on N months" if N < 6) under the card. Tapping
  it **applies immediately** via the existing `setForCategory` / `setOverall`
  (matches the literal request: "click it, sets as budget, still editable
  after" — user then edits via the existing edit flow if they want to
  change it). Decision, flagged for review: apply-instantly, not a prefilled
  review sheet.
- **Nudge**: NOT a real OS notification — `scheduleMonthlyReport`'s
  `zonedSchedule` pattern fires unconditionally (no Dart runs at fire time to
  check state, since this app has no background execution by design); a
  conditional system notification would require the background-job infra
  already rejected for backup. Instead: an in-app banner, shown via the same
  app-open/resume check pattern as `monthlyRecapCheckProvider` — on app
  open/resume, if today is within the last 3 days of the month AND next
  month's overall budget is still unset, show a dismissible banner prompting
  to set it. Guarded by a "last nudged month" setting key so it shows at most
  once per month-transition. Miss: if the app isn't opened in that 3-day
  window, no nudge fires — accepted, same limitation the existing recap check
  already has. Decision, flagged for review: 3-day lead time is a starting
  guess, easy to tune.

## Edge cases

- Brand-new user / brand-new category: no recommendation shown, screen
  behaves exactly as today.
- Category renamed: unaffected — keyed by `categoryId`, not name.
- Category's entire spend history is trip-tagged: treated as zero-history,
  no recommendation shown.
- Category archived or `isIgnoredForBudget`: excluded from recommendation,
  consistent with it already being excluded from budget totals.

## Testing

- Pure recommendation function: direct unit tests — weighting math, outlier
  drop (and the ≥4-month guard not firing early), insufficient-data (0-5
  months), all-history-trip-excluded, ignored/archived category exclusion.
- New repository query: unit test against an in-memory `AppDatabase` (matches
  existing `budget_repository_test.dart` style).
- Provider: tested via `ProviderContainer`, no widget pump (per project
  convention — Drift streams + fl_chart never settle with `pumpAndSettle`).
- No new manual/regression surface beyond what implementation review will
  scope — full impact/regression assessment to be delivered after
  implementation, as requested separately.

## Open items resolved in this spec (flagged for your review)

1. Tap-to-apply sets the value **instantly** (not a prefilled review sheet).
2. Nudge notification fires **3 days before month-end**.

Both are cheap to change if you'd rather go the other way — call it out during
spec review and it'll be adjusted before the implementation plan is written.

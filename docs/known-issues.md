# Spendly — Known Issues & Architectural Push-backs

Consolidated from [`docs/architecture.md`](architecture.md) (§8, §11) and the ADRs in
[`docs/adr/`](adr/). Two lists: bugs that actually shipped and got fixed, and open
architectural weak spots that haven't caused a user-visible bug yet but are one accident away
from it.

---

## 1. Shipped bugs (already fixed)

All are instances of the same underlying pattern (see push-back #1 below) except the two iOS
deep-link issues.

### Reactive-read staleness after a write — hit 3 times independently

A Riverpod `Provider`/`FutureProvider` cached the last-emitted value of a Drift `.watch()`
stream, or was a one-shot fetch never invalidated — so it read **stale data** right after a
write, before the underlying stream had re-emitted (or at all, for the one-shot case).

| Commit | Symptom | Root cause | Fix |
|---|---|---|---|
| `ff334a2` | Widget push-refresh sometimes carried pre-edit category/budget data | `refreshWidgets()` read `categoriesByIdProvider`/`perCategoryBudgetsProvider` — cached `Provider`s built from a stream's last-emitted `.value`, not re-queried at refresh time | Switched to fresh one-shot `.watch().first` reads for categories and budget rows, matching the pattern already used for totals |
| `dd6724f` | Reports screen went stale after add/edit/delete while Home stayed correct | `reportProvider` was a one-shot `FutureProvider`, never invalidated after a mutation | Switched to a `StreamProvider` over `ExpenseRepository.watchInRange`, so Reports reacts the same way Home does |
| `3f52b18` | Budget per-category spend didn't update after add/delete | `categorySpendForMonthProvider` was a one-shot `FutureProvider` over a `.get()` query, cached forever | Switched to `StreamProvider` + a new `watchTotalsByCategory` |

**Note:** three separate fixes, three separate call sites, same root cause each time. None of
the three fixes addressed the general rule — see push-back #1.

### Widget refresh never wired up for budget-setup edits

| Commit | Symptom | Root cause | Fix |
|---|---|---|---|
| `b45de67` | Editing/deleting a budget, toggling "ignore for budget," or using carry-forward didn't update the home-screen widget until the next cold start/resume | Those screens mutated the DB but never called `refreshWidgets()` — there's no shared "on write, refresh" hook, so each screen has to remember to call it itself | Added explicit `refreshWidgets(ref)` calls at all 6 edit sites in `budget_setup_screen.dart` |

### iOS widget deep links silently swallowed

| Commit | Symptom | Root cause | Fix |
|---|---|---|---|
| `9fc2c9e` | Tapping a Quick-Add category chip on the iOS widget did nothing | The `home_widget` plugin only forwards tap URLs carrying a `homeWidget` query marker; the widget's `Link` URLs lacked it (Android's deep link never needed this — plugin quirk specific to iOS) | Appended `&homeWidget` to both `Link` destinations in `SpendlyWidget.swift` |
| `dd6724f` (bundled with the Reports fix above, plus an unrelated app-icon-cropping fix) | Same symptom as above, earlier in the timeline — even a correctly-marked URL never arrived | The `spendly://` URL scheme was never registered on iOS at all | Added `CFBundleURLTypes` to `ios/Runner/Info.plist` |

Two independent iOS-only gotchas, both now fixed, both undocumented plugin behavior at the
time they were hit — flagged in `docs/architecture.md` §1.2 as evidence the widget bridge is
fragile in ways that are easy to miss.

---

## 2. Architectural push-backs (open, not bugs yet)

Ranked by how likely a recurrence is, per `docs/architecture.md` §8/§11.

### 1. No systemic fix for the reactive-read staleness pattern

**Fragile because:** the fix has been applied three times at three call sites, never at the
root. Nothing stops a fourth screen from being built the same wrong way tomorrow.
**Trigger to revisit:** a 4th independent instance of the same bug class in a new feature.
**Fix direction:** a written convention (ideally a lint) — any provider feeding a
just-written UI surface must use a fresh stream subscription, never a cached last-value
`Provider`. Point at the three commits above as the reason it exists.

### 2. Widget bridge schema is hand-triplicated across Dart, Swift, and Kotlin

**Fragile because:** snapshot key names, the App Group id (`group.com.spendly.spendly`), and
widget-kind strings are independently declared in three languages, kept in sync only by
source comments. Already caused both iOS bugs above before being caught.
**Trigger to revisit:** any new snapshot key or widget-kind added, or a third
duplication-caused bug.
**Fix direction:** not full 3-language codegen (disproportionate for a ~6-8 key snapshot at
this scale) — instead, a regression test that snapshot-writes known keys and asserts the
Swift/Kotlin source still references them, so a renamed/removed key fails CI instead of
breaking a widget silently at runtime.

### 3. No centralized "on write, refresh widgets" hook

**Fragile because:** 7 call sites manually invoke `refreshWidgets(ref)`; already missed once
(`b45de67`). Every new mutating screen has to remember to add the call itself.
**Trigger to revisit:** a 4th missed call site.
**Fix direction:** a repository-level "totals changed" notifier that `widget_refresh.dart`
subscribes to once, removing the per-call-site burden — worth it only once the current
per-screen discipline actually fails again.

### 4. No migration-safety test harness

**Fragile because:** schema is at manual version 6, upgraded via a linear `if (from < N)`
chain in `onUpgrade`, with no automated check that upgrading v1→v6 actually produces the
expected schema. `drift_dev` is present but only used for codegen, not schema verification.
**Trigger to revisit:** before the next schema-changing sprint — cheap now, expensive to
retrofit after more versions accumulate untested.
**Fix direction:** add `drift_dev`'s schema export + a golden migration test.

### 5. ~~Backup Merge matches records by name/content-fingerprint, not stable ID~~ — Resolved

Every row (`categories`, `expenses`, `tags`, `budgets`) now carries a nullable `externalId`
(UUID v4, schema v7 — `lib/core/db/external_id.dart`), assigned automatically to every new
row via Drift's `clientDefault` and backfilled immediately for pre-existing rows by the v7
migration. Merge restore now matches by `externalId` first; the old
name/fingerprint matching is kept only as a fallback for rows created before the migration or
backup files exported before this change. Renaming a category between backup and restore no
longer creates a duplicate, for any row that has an `externalId` — covered by a new test
(`test/backup_repository_test.dart`, "renaming a category then merging..."). See
`docs/backup-schema.md` and `docs/architecture.md` §11 risk #5 for the residual fallback path
(still real, but now a deliberate compatibility path rather than an open gap).

### 6. Widget freshness vs. OS reload budgets — unresolved, not just undocumented

**Fragile because:** widget refresh is push-based (`reloadTimelines` after every write), but
iOS WidgetKit throttles that call under a system-managed budget, and Android Glance has its
own update-frequency ceiling. The 1-hour iOS periodic safety net is a coarse fallback for
missed pushes, not a real answer to budget exhaustion under rapid successive writes (e.g.
several Quick Adds in a row).
**Trigger to revisit:** a user-reported "widget shows stale total" complaint under heavy use.
**Fix direction:** none proposed yet — flagged as an open tension in `docs/architecture.md`
§1.2, not a solved problem.

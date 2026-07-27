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

### 1. ~~No systemic fix for the reactive-read staleness pattern~~ — Resolved

A real `custom_lint`/`riverpod_lint` rule was considered and rejected: this repo uses
classic Riverpod provider declarations (no `@riverpod` codegen), and both packages pin
`analyzer` version ranges that carry the same lockstep-conflict risk already documented in
push-back #4 below (where it actually blocked `drift_dev`) — untested added risk, not a
quick win.

Landed a source-scanning test instead, `test/reactive_read_staleness_test.dart` (same style
as `migration_test.dart`): it classifies every Riverpod provider in `lib/` as "data-backed"
(a `StreamProvider`, a `FutureProvider`, or a plain `Provider` derived from
`ref.watch(x).value`) or safe (repo/service instances, self-mutating `Notifier`/
`AsyncNotifierProvider`s), then fails if any data-backed provider is read via `ref.read()`
anywhere — the shared shape behind all three original incidents, generalized: `ref.watch()`
in a widget build is always safe (the widget rebuilds on the next emission); `ref.read()` on
a data-backed provider serves neither live reactivity nor a guaranteed-fresh value, so it's
banned outright rather than checked case-by-case.

Writing the test's manual-grep precursor immediately caught a previously-undocumented
**4th live instance**, never fixed until now:
`lib/features/expenses/quick_add_screen.dart`'s `_checkBudgetAlerts` — called right after
every expense add/edit — read `perCategoryBudgetsForMonthProvider`, `categoriesByIdProvider`,
and `overallBudgetForMonthProvider` via `ref.read(...)` right after the write the alert is
supposed to react to, so an 80%/100% budget-threshold notification could evaluate against
pre-write budget/category data. A 5th, lower-stakes instance turned up in
`widget_refresh.dart` itself (`lastUsedCategoryIdProvider`, used to order the widget's
quick-add category chips). Both fixed with fresh one-shot repository reads, matching the
pattern `widget_refresh.dart` already established for the three original fixes.

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

### 3. ~~No centralized "on write, refresh widgets" hook~~ — Resolved

Was worse than "7 call sites to remember": there were 10, plus at least 8 more mutations
(`ExpenseRepository.delete`, all of `CategoryRepository`'s and `TagRepository`'s CRUD) that
already shipped with no refresh call at all — the widget was silently stale for a swipe-delete
or a category rename, independent of any future missed site.

`widget_refresh.dart` now subscribes once to Drift's own `AppDatabase.tableUpdates()` stream
(`widgetRefreshHookProvider`, armed once in `app.dart`), scoped to the `expenses`/`categories`/
`budgets` tables and debounced 250ms. Every write through Drift — insert, update, delete, batch,
transaction — fires it, so no call site can forget. All 10 manual `refreshWidgets(ref)` call
sites were deleted; `refreshWidgets` itself now takes a `Ref` (Riverpod 3 split `Ref` and
`WidgetRef` into unrelated types, so the two remaining widget-tree calls — app cold-start/resume,
not writes — go through a new `refreshWidgetsActionProvider` closure instead of calling it
directly). Covered by `test/widget_refresh_hook_test.dart`: inserts an expense with no explicit
refresh call and asserts the widget snapshot updates anyway.

### 4. ~~No migration-safety test harness~~ — Resolved

Schema is at manual version 7 (corrected from "6" above — v7/externalId already shipped by
the time this was written), upgraded via a linear `if (from < N)` chain in `onUpgrade`. Added
`test/migration_test.dart`: seeds a real v1 schema (raw SQL, reconstructed from commit
`aaf6d2f`) with pre-existing rows, opens it as the current `AppDatabase`, and lets the real
`onUpgrade` chain run v1→v7 in one pass — the same thing a user who hasn't updated in a long
time would hit.

The original fix direction (`drift_dev`'s schema-export + `SchemaVerifier` tooling) turned out
to be blocked in this environment: `drift_dev`'s `schema dump` command crashes even on the
current schema (patch mismatch between the pinned `drift 2.34.2` / `drift_dev 2.34.0`), and
bumping `drift_dev` past it requires an `analyzer` major bump that collides with `test_api`
pinned by the installed Flutter SDK itself — not fixable via `pubspec.yaml` alone. Landed a
hand-rolled raw-SQL harness instead: no new dependencies, same coverage.

Writing the very first version of this test immediately caught three real, already-shipping
bugs in the `onUpgrade` chain — all three followed the same pattern (a migration step reached
for a "live schema" helper — `m.createTable`, `insertAll` with a `clientDefault` column —
instead of raw SQL scoped to the historical shape at that point in the chain):

1. `budgets.monthKey` added via `m.addColumn` with no default — SQLite rejects `ADD COLUMN
   ... NOT NULL` with no default the moment the table has an existing row. Any user with a
   saved budget upgrading from v1 would crash on every launch. Fixed with a raw
   `ALTER TABLE ... ADD COLUMN month_key TEXT` (nullable at the DDL level; the existing
   immediate `UPDATE` backfill still runs right after).
2. The v3 category-seed step used `CategoriesCompanion.insert`, which always writes every
   *current* column via `clientDefault` — including `external_id`, four migration blocks
   before that column exists. Crashed for anyone upgrading from v1/v2/v3. Fixed with a raw
   `INSERT` naming only the columns that existed at v3.
3. `m.createTable(tags)` (from<4) always builds the table using the live, current `Tags`
   definition — meaning anyone upgrading from below v4 got `tags` created *already* with
   `external_id`, and the later unconditional `m.addColumn(tags, tags.externalId)` (from<7)
   then failed with a duplicate-column error. Fixed by checking `PRAGMA table_info(tags)`
   before adding the column.

None of these had ever been exercised — every existing DB test only opened a fresh
`AppDatabase` at the current version (`onCreate`), never simulated an upgrade (`onUpgrade`).
See `lib/core/db/database.dart`'s `onUpgrade` chain and the doc comment above `schemaVersion`
for the go-forward convention: extend `test/migration_test.dart` with a new seeded row whenever
a schema bump adds an `onUpgrade` block.

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

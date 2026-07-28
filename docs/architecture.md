# Spendly — Architecture Documentation

Written against the codebase as of Sprint 12+ (Drift schema v7, backup format v3). Follows
the [arc42](https://arc42.org) template. This document reflects what the
code actually does, verified against source — not an idealized target architecture. Where a
decision has trade-offs or a documented weak spot, that is stated plainly rather than glossed
over; see §11 for the consolidated risk register.

Individual architecture decisions are recorded as ADRs in [`docs/adr/`](adr/), linked from
§9.

---

## 1. Introduction and Goals

### 1.1 Requirements overview

Spendly is a single-user, offline-first personal expense tracker (Flutter, iOS + Android)
covering: quick expense entry, category and budget management, trip-based grouping (internally
called "tags"), monthly/custom reports with PDF/CSV export, home-screen widgets, local
notifications for recurring-expense reminders and budget thresholds, and versioned encrypted
backup/restore. Full functional spec: [`requirement_docs/spendly-requirements.md`](../requirement_docs/spendly-requirements.md)
(FR-numbered) and the clickable prototype at [`requirement_docs/spendly-prototype.html`](../requirement_docs/spendly-prototype.html).

### 1.2 Quality goals

Ranked by what actually matters for this app, with conflicts stated explicitly rather than
listed as if they were all simultaneously free.

1. **Offline-first correctness.** The app must work fully with no network, always. This is
   genuinely strong today: there are no networking dependencies in `pubspec.yaml` at all (no
   `http`, `dio`, `connectivity_plus`), so nothing in the core read/write path — expense CRUD,
   budgets, categories, reports, dashboard — can make a network call even by accident. Nothing
   to push back on here; this goal is met by construction, not by discipline.

2. **Widget data freshness — in real tension with the OS, not fully solved.** Widgets are
   refreshed by an explicit push (`refreshWidgets()` → `HomeWidget.updateWidget` →
   `WidgetCenter.reloadTimelines`) after every write, which is the right default strategy. But
   iOS WidgetKit throttles `reloadTimelines` calls under a system-managed budget, and Android
   Glance has its own update-frequency ceiling — neither is unlimited. The 1-hour periodic
   iOS timeline refresh (`SpendlyWidget.swift`) is a safety net for missed pushes, not a real
   answer to budget exhaustion under heavy use (e.g. rapid successive Quick Adds). This is an
   **unresolved tension** between "instant freshness" and "the OS won't let you push
   unlimited reloads" — flagged honestly rather than presented as solved. See ADR-006.

3. **Backup/restore data integrity — not "sync consistency."** There is no multi-device sync
   in this app, live or otherwise (see §3, ADR-004) — the correct quality goal is *the backup
   file, once restored, faithfully reconstructs the data a user intended to keep*. **Fixed**:
   every row now carries a stable `externalId` (UUID), and Merge restore matches by that id
   first, falling back to natural key / content fingerprint (name for categories/tags,
   `(amountMinor, date, categoryId, note, paymentMethod)` for expenses) only for rows/files
   that predate the migration. Renaming a category between backup and restore no longer
   creates a duplicate for any row with an `externalId`. See `docs/backup-schema.md` and
   ADR-004; the residual fallback path (pre-migration rows, legacy backup files) is tracked
   in §11 risk #5.

4. **Solo-maintainability / development velocity.** Feature-first modules, repositories
   co-located with their Riverpod providers, no enforced layering. Cheap to work in for one
   person at this app's size — but it already shows strain: the same class of bug (a cached
   Riverpod provider reading a Drift stream's stale last value right after a write) has been
   independently hit and separately patched three times (widget snapshot, reports screen,
   budget per-category spend — see §8). That is a signal the "velocity" trade-off is starting
   to cost more than it saves in one specific place, even though the overall structure remains
   appropriate for the app's size. See ADR-001, §8.

5. **Cross-platform consistency of the widget bridge.** Directly in tension with #4: the
   snapshot schema (keys, App Group id, widget-kind strings) is hand-declared independently in
   Dart, Swift, and Kotlin, enforced only by source comments telling the next editor to keep
   them in sync by hand. This has already caused two real, shipped bugs (iOS URL scheme not
   registered; `home_widget`'s `homeWidget` tap-marker requirement missed) before being fixed.
   Fast to write per-platform, fragile to keep correct. See ADR-005, §8.

### 1.3 Stakeholders

Solo developer (build + maintain); end users (personal single-currency finance tracking, no
accounts, own their data locally and via their own backup destination of choice).

---

## 2. Architecture Constraints

- **No backend/server, by design** — not a resourcing gap. Zero server-side dependencies
  anywhere in the codebase. See ADR-004.
- **Three languages, three toolchains**: Dart/Flutter (app), Swift (iOS WidgetKit extension,
  `ios/SpendlyWidget/`), Kotlin (Android Glance widget,
  `android/app/src/main/kotlin/.../widget/`). Every widget-bridge change has to be reasoned
  about in all three.
- **Single currency v1** — `Money` (`lib/core/money/money.dart`) hardcodes INR/`en_IN`
  formatting; there is no currency-code column in the schema. Documented as a deferred v2
  scope decision (`ponytail:` comment in source), not an absent feature. See ADR-008.
- **Riverpod is the only composition mechanism** — no `get_it`/`injectable`, no router
  package (`go_router`/`auto_route`). All DI flows through the provider graph; all navigation
  is imperative `Navigator.push`. See ADR-002, ADR-007.
- **Pinned dependency versions** for native-toolchain reasons (`file_picker 10.3.10`,
  `share_plus ^12`) and an iOS deployment target set higher than the real functional floor —
  see PROGRESS.md's "Stack / tooling" notes before bumping either.

---

## 3. System Scope and Context

### 3.1 In scope

Single-user local expense/category/budget/trip tracking; reports with PDF/CSV export;
home-screen widgets (iOS WidgetKit ×4 variants, one adaptive Android Glance widget) with
quick-add deep linking; local notifications for recurring-expense reminders (the app reminds,
the user confirms on the due date — it never auto-logs) and budget threshold alerts; local
AES-256-GCM/PBKDF2-encrypted backup export via the OS share sheet; automatic local-only
snapshot writer on app launch/resume; manual pull-based restore with a Merge/Replace choice.

### 3.2 Out of scope (explicit non-goals)

These are decisions, not gaps — each has an ADR or is called out in §1/§8 where relevant:

- Multi-device live sync (no account, no server, no conflict resolution beyond best-effort
  Merge matching) — ADR-004.
- Any backend/server component.
- User accounts or authentication.
- Multi-currency — ADR-008.
- Server-push notifications (all notifications are locally scheduled).
- Telemetry/analytics backend.
- Bank feed or payment integrations.

### 3.3 Context overview

```
        ┌────────────┐
        │    User     │
        └─────┬──────┘
              │ interacts with
              ▼
        ┌─────────────────────────────┐
        │         Spendly app          │
        │   (Flutter, single binary)   │
        └───┬─────────┬──────────┬────┘
            │         │          │
            ▼         ▼          ▼
   ┌────────────┐ ┌──────────┐ ┌───────────────────┐
   │ Local SQLite│ │ OS share  │ │ Home-screen widget │
   │  (Drift DB) │ │ sheet     │ │ surfaces (iOS/     │
   │             │ │ (opaque   │ │ Android) via App    │
   │             │ │ destination│ │ Group / shared     │
   │             │ │ chosen by │ │ prefs               │
   │             │ │ user)     │ │                     │
   └────────────┘ └──────────┘ └───────────────────┘
            ▲
            │
   ┌────────────────────┐
   │ Local notification  │
   │ scheduler            │
   └────────────────────┘
```

The OS share sheet is a boundary the app treats as opaque — Spendly has no idea and no
control over where the user actually sends a backup file (iCloud Drive, Google Drive, email,
AirDrop, etc.). That is the entire "cloud" story.

---

## 4. Solution Strategy

Feature-first module organization (§5) with Riverpod as the single mechanism for both state
management and dependency composition (ADR-001, ADR-002). Drift/SQLite provides reactive
local persistence — UI reads are live stream subscriptions, not one-shot fetches, which is
what makes "update the DB, UI follows" the default interaction pattern app-wide (ADR-003).
Home-screen widgets are a thin read-only projection of the same data, kept in sync by an
explicit push after every write rather than polling (ADR-006), bridged to native code via a
hand-maintained shared-storage schema (ADR-005). There is deliberately no backend: all
"cloud" behavior is local file export handed to the OS share sheet (ADR-004).

---

## 5. Building Block View

### 5.1 Level 1 — top-level decomposition

```
lib/
├── main.dart, app.dart     boot, root routing (onboarding vs home), app lifecycle hooks
├── core/                    genuinely cross-cutting only
│   ├── db/                  Drift database, schema/migrations, row extensions
│   ├── money/                integer-minor-unit Money type + locale formatting
│   ├── notify/                local notifications + appNavigatorKey (external-push navigation)
│   ├── theme/                 tokens, light/dark ThemeData
│   └── widgets/                shared UI (keypad, cards, async-state views, glyphs)
└── features/                 one folder per domain area (13 total)
    ├── expenses/ categories/ budgets/ reports/ tags/       core domain features
    ├── home/ onboarding/ profile/ settings/                 app-shell/user features
    ├── backup/ widgets/                                      cross-cutting product features
    └── dev/                                                   dev-only debug tooling
```

Nothing domain-specific lives in `core/` — it's strictly DB plumbing, the money value type,
notification wiring, theming tokens, and shared presentational widgets.

### 5.2 Level 2 — the per-feature shape

Every feature folder repeats the same internal pattern: one or more screens, a repository
class holding an `AppDatabase` reference and writing Drift queries directly (no DAO layer,
no repository interface — `ExpenseRepository`, `CategoryRepository`, `BudgetRepository`,
`TagRepository`, `SettingsRepository`), and Riverpod providers exposing that repository's
data to the UI, usually all in the same 1-3 files (e.g.
`lib/features/expenses/expense_repository.dart` holds the repository *and* its providers).
Drift rows are extended with domain getters (`lib/core/db/row_extensions.dart`, e.g.
`ExpenseRow.amount → Money`) rather than mapped into separate parallel model classes.

**This is a documented choice, not an oversight**: there is no data/domain/presentation
layering anywhere in the app, and none is proposed here. See ADR-001 for why, and §8/§11 for
where this trade-off is starting to cost more than it saves.

### 5.3 Native widget extensions

- `ios/SpendlyWidget/SpendlyWidget.swift` — a single `WidgetBundle` with 4 widgets
  (`SpendlyTodayWidget`, `SpendlyQuickAddWidget`, `SpendlyMonthWidget`, `SpendlyLockWidget`).
- `android/app/src/main/kotlin/com/spendly/spendly/widget/SpendlyGlanceWidget.kt` — one
  adaptive Jetpack Glance layout for all sizes, plus a thin `SpendlyWidgetReceiver.kt`.
- Both read the same flat key/value snapshot written by `lib/features/widgets/widget_snapshot.dart`
  (see §5.4, §8).

### 5.4 The widget bridge

Single canonical builder: `buildWidgetSnapshot()` (`lib/features/widgets/widget_snapshot.dart:52-99`),
a pure, unit-tested function producing a `Map<String, String>` — all money pre-formatted
app-side (`en_IN` locale), so native code never does currency math. Key names are centralized
as Dart constants (`WidgetKeys`) with a comment noting Swift/Kotlin "can't silently drift
apart" — but there is no codegen enforcing that; see §8.

---

## 6. Runtime View

Four scenarios that best show how the pieces interact:

**Quick Add → dashboard → widget.**
User submits Quick Add → `ExpenseRepository` writes the row → Drift's `.watch()` stream
re-emits → dashboard `StreamProvider`s (`dashboard_providers.dart`) rebuild the donut/trend/
budget bar → `quick_add_screen.dart` explicitly calls `refreshWidgets(ref)` → fresh one-shot
reads rebuild the snapshot → `WidgetBridge().write()` saves it and calls
`HomeWidget.updateWidget` → native `reloadTimelines`/broadcast → widget UI updates.

**Widget tap → Quick Add, pre-filled.**
User taps a Quick Add category chip on the widget → native side opens
`spendly://quickadd?category=<id>` (iOS appends a `&homeWidget` marker required by the
`home_widget` plugin to forward the tap) → `HomeWidget.widgetClicked` stream fires in
`app.dart` → `_handleWidgetUri` pushes `QuickAddScreen(initialCategoryId: id)` via the global
`appNavigatorKey` (used specifically because this navigation originates outside the widget
tree).

**Backup restore (Merge).**
User picks a backup file → `backup_import.dart` reads and validates it → user chooses
Merge → `backup_repository.dart` matches categories/tags by lower-cased trimmed name, budgets
by category slot, and expenses by a content fingerprint
(`amountMinor, date, categoryId, note, paymentMethod`) → unmatched records are inserted,
matched records are left alone (additive, never authoritative reconciliation) →
`restore_screen.dart` calls `refreshWidgets(ref)` afterward so widgets don't show pre-restore
totals.

**Recurring expense reminder.**
A scheduled local notification fires on the due date → user taps it → app routes to a
pre-filled Quick Add via `appNavigatorKey` (same pattern as the widget-tap case) → user
confirms → expense is logged. The system never logs on the user's behalf.

---

## 7. Deployment View

Deliberately minimal — there is nothing to deploy beyond the app itself:

- Two mobile binaries (iOS, Android), same Dart codebase, platform-specific widget
  extensions built alongside.
- One local SQLite file (`spendly.sqlite`) in the app's documents directory, created and
  seeded (18 default categories) on first launch.
- Widget data lives in the App Group container (iOS, suite `group.com.spendly.spendly`) or
  shared preferences (Android), written by the app, read by the widget process.
- No servers, no environments beyond debug/release build configurations.

---

## 8. Crosscutting Concepts

Four systemic issues surfaced across otherwise-unrelated features — grouped here because
each is a *pattern*, not an isolated bug, and each recurrence is evidence the underlying rule
isn't written down anywhere yet.

### 8.1 Reactive-read staleness after a write

A Riverpod `Provider`/`FutureProvider` that caches the last-emitted value of a Drift
`.watch()` stream can read **stale data immediately after a write**, because the stream has
not re-emitted yet (at least one microtask of lag). This has been hit and separately
patched three times, each treated as a one-off bug at the time:

- Widget snapshot read stale category/budget data right after an edit (commit `ff334a2`).
- The reports screen had the identical issue (commit `dd6724f`).
- Budget per-category spend didn't update after add/delete (commit `3f52b18`).

Each fix replaced the cached provider with a fresh one-shot read (`.watch().first` or
equivalent) at that specific call site. None of the three fixes addressed the general rule.

**Recommended fix direction:** adopt (and ideally lint for) a convention: *any provider that
feeds a UI surface expected to reflect a just-completed write must read via a fresh stream
subscription, never a cached last-value `Provider`.* Point future contributors at these three
incidents as the reason the rule exists, not just an abstract best practice.

### 8.2 Widget-bridge schema duplication

The snapshot's key names, the App Group / shared-prefs suite id (`group.com.spendly.spendly`),
and the widget-kind strings are each hand-declared independently in Dart (`WidgetKeys`,
`widget_snapshot.dart`), Swift (`Decodable` structs, `SpendlyWidget.swift`), and Kotlin
(manual `JSONArray`/`getJSONObject` parsing, `SpendlyGlanceWidget.kt`). The only thing
keeping them in sync is source comments asking the next editor to update all three by hand.
This has already caused two shipped bugs before being caught: the `spendly://` URL scheme not
being registered in `Info.plist` (commit `dd6724f`), and the `home_widget` plugin's required
`homeWidget` tap-marker being missing from the iOS `Link` URLs (commit `9fc2c9e`).

**Recommended fix direction:** full 3-language codegen is likely disproportionate effort for
a solo-maintained app at this size — naming that trade-off explicitly rather than prescribing
it. A cheaper, still-effective option: a small regression test that snapshot-writes each known
key/id and asserts the Swift and Kotlin source files still reference it (a regex-based drift
check), so a renamed or removed key fails CI instead of silently breaking a widget at runtime.

### 8.3 Centralized write→refresh hook for widgets — resolved

Previously `refreshWidgets(ref)` was called explicitly from every mutating screen — at peak,
10 manual call sites, plus at least 8 further mutations (`ExpenseRepository.delete`, all
`CategoryRepository`/`TagRepository` CRUD) that had already shipped with no refresh call at
all. This is now fixed structurally: `widgetRefreshHookProvider`
(`lib/features/widgets/widget_refresh.dart`) subscribes once to Drift's own
`AppDatabase.tableUpdates()` stream, scoped to the `expenses`/`categories`/`budgets` tables
and debounced 250ms, so every write triggers a refresh with no per-call-site discipline
required. All prior manual call sites were deleted; the only two remaining calls to
`refreshWidgets` are cold-start and app-resume, routed through
`refreshWidgetsActionProvider`. Regression-guarded by
`test/widget_refresh_hook_test.dart`.

### 8.4 No migration-safety test harness

Schema migrations use a manual `schemaVersion` integer (currently 6) and a linear
`if (from < N) { ... }` chain in `onUpgrade` (`lib/core/db/database.dart`). `drift_dev` is
present as a dev dependency for code generation only — there is no schema-export/golden
migration test verifying that upgrading a v1 database through to v6 actually produces the
expected v6 schema. Today this is caught (if at all) by manual review.

**Recommended fix direction:** add `drift_dev`'s schema export + a golden migration test
before the next schema-changing sprint. Cheap now, at v6; materially more expensive to
retrofit once more versions and more upgrade paths have accumulated untested.

### 8.5 A positive convention worth keeping

`Money` (`lib/core/money/money.dart`) stores and computes exclusively in integer minor units
— `amountMinor: int` in the schema, no `double` anywhere in storage or arithmetic, and
`Money.parse` parses decimal strings digit-by-digit specifically to avoid binary
floating-point rounding. `major` (a `double`) exists only for display formatting and is
explicitly documented "never for math." This is the one place in the app where a systemic
rule *is* written down and consistently followed — worth calling out as the standard the
issues above should be brought up to, not just a list of what's wrong.

---

## 9. Architecture Decisions

Full detail (context, alternatives considered, consequences) lives in `docs/adr/`. Summary:

| ADR | Decision |
|---|---|
| [ADR-001](adr/001-feature-first-structure.md) | Feature-first module structure, no data/domain/presentation layering |
| [ADR-002](adr/002-riverpod-state-and-di.md) | Riverpod as the sole state management + dependency-composition mechanism |
| [ADR-003](adr/003-drift-local-persistence.md) | Drift/SQLite for local persistence, no repository-interface abstraction over it |
| [ADR-004](adr/004-no-cloud-sync.md) | No cloud sync — local export/import via the OS share sheet only |
| [ADR-005](adr/005-widget-bridge-shared-storage.md) | Widget bridge via `home_widget` + hand-mirrored shared-storage schema |
| [ADR-006](adr/006-push-based-widget-refresh.md) | Push-based widget refresh via a centralized Drift `tableUpdates()` hook |
| [ADR-007](adr/007-imperative-navigation.md) | Imperative `Navigator` + `MaterialPageRoute`, no router package |
| [ADR-008](adr/008-money-and-currency-model.md) | Integer-minor-units `Money`, single hardcoded currency (INR) for v1 |
| [ADR-009](adr/009-testing-strategy.md) | Testing via `ProviderContainer` + in-memory Drift, no widget-pump/`pumpAndSettle`, no golden or integration tests yet |

---

## 10. Quality Requirements

Concrete scenarios expanding §1.2's goals — stated as currently-true-or-not, not aspirational:

| Scenario | Current status |
|---|---|
| App is fully usable (add/edit/view/report) with the device in airplane mode | **Met** — no networking code exists in the core path (§1.2 #1). |
| A widget reflects a Quick Add save within a few seconds under normal use | **Usually met**, push-based; **not guaranteed** under iOS reload-budget pressure from rapid successive writes (§1.2 #2, §8.1). |
| Restoring a backup on the same device it was taken from reproduces the data exactly | **Met** for Replace mode. |
| Restoring a backup after renaming a category since the backup was taken does not create a duplicate category | **Not met** — documented known limitation of name-based Merge matching (§1.2 #3, `docs/backup-schema.md`). |
| Editing a budget or category updates dashboard, reports, and widgets without a manual refresh | **Met**, but has required three separate bug fixes to reach (§8.1) — regression risk on any new write path is real until the underlying rule is enforced, not just followed by convention. |
| A schema migration from any prior version to the current version produces the expected schema | **Unverified** — no automated check exists (§8.4). |

---

## 11. Risks and Technical Debt

Consolidated register — the four crosscutting issues from §8, plus backup Merge's matching
limitation from §1.2 #3. See [`docs/known-issues.md`](known-issues.md) for this same
register alongside the concrete shipped bugs (with commit hashes) each pattern has already
caused.

| # | Risk | Current cost | Revisit trigger | Fix direction |
|---|---|---|---|---|
| 1 | Reactive-read staleness after writes (§8.1) | Low per-incident, but has recurred 3× independently | A 4th independent instance in a new feature | Convention + lint: always fresh-read after a write, never cached-provider |
| 2 | Widget-bridge schema triplication (§8.2) | Two shipped bugs so far, both iOS-specific | Any new snapshot key or widget-kind added | Regex-based drift test between Dart source and Swift/Kotlin source, not full codegen |
| 3 | Widget-refresh hook centralization (§8.3) | **Fixed** — Drift `tableUpdates()` hook replaces all manual call sites | n/a | Guarded by `test/widget_refresh_hook_test.dart` |
| 4 | No migration-safety test harness (§8.4) | None yet realized — schema is at v6 with no incident | Before the next schema-changing sprint | `drift_dev` schema export + golden migration test |
| 5 | Backup Merge natural-key/fingerprint fallback (§1.2 #3) | **Fixed** for `externalId`-bearing rows (schema v7+). Residual: rows from before the migration and backup files exported before it still rely on the old natural-key/fingerprint matching | A future backup file predating schema v7 gets merged | None needed further — the fallback is an intentionally permanent compatibility path, not a gap to close |

---

## 12. Glossary

| Term | Meaning |
|---|---|
| Money / minor units | Amounts stored and computed as integers in the currency's smallest unit (paise for INR) — never floats. `lib/core/money/money.dart`. |
| Trip | User-facing name for what the codebase calls a **Tag** (`lib/features/tags/`) — a label grouping expenses independent of category. |
| Quick Add | The primary expense-entry flow: numeric keypad, top category grid, optional note/trip/payment method. |
| Snapshot | The flat key/value map (`buildWidgetSnapshot()`) written to shared storage for native widgets to render. |
| Merge vs. Replace | The two restore modes: Merge additively inserts unmatched records (never overwrites); Replace wipes and reloads from the backup file. |
| App Group | iOS's shared-storage mechanism (`group.com.spendly.spendly`) letting the main app and the WidgetKit extension read/write the same `UserDefaults` suite. |

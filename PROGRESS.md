# Spendly — Progress

> Cross-session shared memory. Read this first every session. Update it at the
> end of every sprint before stopping.

## Current status

- **Sprint:** 3 (Categories & Budgets + threshold notifications) — **built, awaiting user verification**
- **Next:** Sprint 4 (Reports) — do NOT start until user gives go.

## Locked decisions (from PRD open questions)

- **Currency:** single currency; symbol + number format follow device locale, default ₹ INR. Multi-currency = v2. (PRD Q1)
- **Recurring (FR-7):** remind + user confirms on due date via local notification; never silent auto-log. (PRD Q3)
- **State management:** Riverpod (`flutter_riverpod`).
- **Local DB:** Drift (SQLite). Money stored as **integer minor units** (paise), never float.
- Still open, resolve before Sprint 5: cloud-sync scope (Q2), backup encryption (Q6), auto-backup default frequency (Q7).

## Stack / tooling

- Flutter 3.44.7 (latest stable) · Dart 3.12.2 · Xcode 26.6 · Android SDK · CocoaPods (all verified present).
- Dependency freshness: **all direct deps latest**. Remaining `pub outdated` flags (analyzer 12, meta, test, build_runner, drift_dev, package_config 2, record_use 0.6, …) are **SDK-pinned by Dart 3.12.2** — `Resolvable == Current`, not bumpable without a newer Flutter/Dart. No `dependency_overrides` (would break). Revisit when stable Flutter ships newer Dart.
- Deps: flutter_riverpod, drift + sqlite3_flutter_libs + path_provider + path, intl, fl_chart, **flutter_local_notifications ^22.1.0** (S3, pulls timezone transitively — unused, alerts are immediate `.show()`). Dev: drift_dev, build_runner, flutter_lints.
- Android needs **core library desugaring** for flutter_local_notifications: `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` in `android/app/build.gradle.kts`. iOS AppDelegate sets `UNUserNotificationCenter.delegate`; `POST_NOTIFICATIONS` in the manifest.
- Fonts bundled as assets (offline-first): `assets/fonts/Sora.ttf`, `assets/fonts/Inter.ttf`.
- Codegen: `dart run build_runner build` (generates `lib/core/db/database.g.dart`).

## Sprint 0 — done

- [x] Scaffold `flutter create` (org com.spendly), feature-first `lib/` layout.
- [x] Design tokens from prototype `:root` → `lib/core/theme/tokens.dart` (colors, gradients, spacing, radii; `AppPalette` ThemeExtension for card/line/textDim).
- [x] Light + dark `ThemeData` → `lib/core/theme/app_theme.dart` (Sora display, Inter body).
- [x] Theme mode = system default + manual override, persisted in settings table (`lib/features/settings/theme_mode_provider.dart`). Toolbar button cycles system→light→dark.
- [x] Drift schema v1: `categories`, `expenses`, `budgets`, `settings` (`lib/core/db/database.dart`). Migration strategy stub in place.
- [x] Money type (int minor units) + locale formatting (`lib/core/money/money.dart`). Parses decimal strings without float — no binary rounding error.
- [x] Empty themed home + bottom-nav shell + FAB (`lib/features/home/home_screen.dart`). Real dashboard = Sprint 2.
- [x] CI: `.github/workflows/ci.yml` (analyze + test on push/PR).
- [x] `spendly-sprint-plan.md` copied to repo root (kickoff references it by name).

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → 10 passed (money math + widget smoke test).

### Deferred / notes
- Fonts are variable TTFs; weights map via `fontWeight`. Fine for v1.
- Category/budget seed data + CRUD deliberately deferred to Sprint 1 per plan.

## Sprint 1 — done (Core Data Layer)

Recurring decision: **date-math + flag only** this sprint (template→confirm reminders = Sprint 3). Verification = in-app debug screen + unit tests.

- [x] Seed 8 default categories (FR-8) in `onCreate` → `lib/core/db/database.dart` (`_defaultCategories`, prototype icons/colors, isDefault=true).
- [x] Row→domain extensions (no parallel models) → `lib/core/db/row_extensions.dart` (`ExpenseRow.amount` = Money, `CategoryRow.color`).
- [x] Category CRUD (FR-9,10,11) → `lib/features/categories/category_repository.dart`: create/rename/recolor/setIcon/reorder/archive/unarchive, watchAll/watchActive. Archive never deletes. Providers: categoryRepositoryProvider, activeCategoriesProvider, allCategoriesProvider.
- [x] Expense CRUD + money-math (FR-1,6) → `lib/features/expenses/expense_repository.dart`: add/update/delete, watchInRange, watchMonth, monthTotal, totalInRange, totalsByCategory. `monthBounds()` helper. Providers: expenseRepositoryProvider + currentMonth{Expenses,Total,CategoryTotals}.
- [x] Recurrence date-math (FR-7) → `lib/features/expenses/recurrence.dart`: `nextOccurrence` (month-end clamp), `occurrencesBetween`. Pure, no DB.
- [x] Debug screen → `lib/features/dev/debug_data_screen.dart`, reachable from Home AppBar bug icon (kDebugMode only). Throwaway.

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **30 passed** (money, recurrence, category repo, expense repo, widget smoke).

### Deferred / notes
- Recurring: no auto-insert/scheduling yet (Sprint 3).
- Debug screen is scaffolding; deleted when real Quick Add (S2) + Category Manager (S3) land.
- No expense↔category join view yet (Sprint 2 need).

## Sprint 2 — done (Home Dashboard & Quick Add)

Decisions: charts via **fl_chart styled to match**; Quick Add preselects **last-used category**.

- [x] Home dashboard (FR-12–16) → `lib/features/home/home_screen.dart`: greeting, hero gradient card (month total + budget bar / "set budget" empty state), donut, 6-mo trend, recent tiles (tap → edit). Bottom nav + FAB.
- [x] Charts → `lib/features/home/widgets/spend_donut.dart` (PieChart+legend), `trend_bars.dart` (BarChart, current month accent). fl_chart styled to prototype.
- [x] Quick Add (FR-2,5,6,15) → `lib/features/expenses/quick_add_screen.dart`: keypad (no OS kbd), category grid, last-used preselect, 2-dp guard, edit mode reused for tapping a transaction.
- [x] Stream-derived dashboard providers (reactive) → `lib/features/home/dashboard_providers.dart`: monthTotal, categoryBreakdown, recent, trend, lastUsedCategoryId + pure funcs (sumMoney/buildBreakdown/trendBuckets). Adding an expense updates Home live — no manual refresh.
- [x] Read-only overall budget → `lib/features/budgets/budget_repository.dart` (full setup = Sprint 3). Shared `lib/core/widgets/app_card.dart` (AppCard, SectionTitle).

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **36 passed** (money, recurrence, repos, dashboard derivations, provider wiring).

### Gotcha recorded
- **Never `pumpAndSettle`** a screen with live Drift streams + fl_chart — it never settles (hangs). Test reactive wiring via `ProviderContainer` instead. See `test/widget_test.dart`.

### Deferred / notes
- Budget is read-only display; budget setup UI + 80/100% notifications = Sprint 3.
- Recent list scoped to current month (newest 10).
- Platform apk/ios build not re-run this sprint (only Dart added, fl_chart is pure-Dart; analyze+test green). Run `flutter run` to verify on device.

## Sprint 3 — done (Categories & Budgets + threshold notifications)

Decisions: notifications via **flutter_local_notifications**, fire at add-time on a budget crossing; budget amounts entered via **keypad sheet** (prototype slider = read-only usage bar).

- [x] Budget CRUD (FR-23,24) → `lib/features/budgets/budget_repository.dart`: `setOverall`/`setForCategory` (find-then-write upsert, no dup rows), `clearForCategory`, `watchAll`. Providers: allBudgetsProvider, perCategoryBudgetsProvider, overallBudgetProvider. Pure `crossedThresholds(before, after, budget)` (integer, exact).
- [x] Notifications (FR-25) → `lib/core/notify/notifications.dart` (`NotificationService.init` in `main`, `showBudgetAlert`). Fired from `quick_add_screen.dart` `_save` → `_checkBudgetAlerts` on the affected category + overall, using before/after of the write delta. Add-time only (offline app: spend only changes via a write).
- [x] Category Manager (FR-9,10,11) → `lib/features/categories/category_manager_screen.dart` (ReorderableListView, archived dimmed, drag handle) + `category_edit_sheet.dart` (rename, ~30-emoji icon picker, brand-palette color picker, archive/unarchive).
- [x] Budget Setup (FR-23,24) → `lib/features/budgets/budget_setup_screen.dart` (overall + per-category cards, usage bar coloured green/accent/red by state, add/edit/clear).
- [x] Shared keypad extracted → `lib/core/widgets/amount_keypad.dart` (`applyAmountKey` pure fn, `AmountKeypad`, `AmountDisplay`, `showAmountSheet`). Quick Add reuses it.
- [x] Nav: Home bottom-nav Categories tab → CategoryManagerScreen; its appbar wallet → BudgetSetupScreen. Settings tab still stub (Sprint 5).

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **49 passed** (+ budget_repository, budget_threshold, amount_keypad).
- `flutter build apk --debug` ✓ · `flutter build ios --debug --simulator --no-codesign` ✓ (both rebuilt — new native dep).

### Deferred / notes
- Alerts fire only on in-app writes (no background re-check) — correct for offline; no per-alert dedup store (crossing computed from before/after, fires once per real crossing).
- `timezone` dep pulled transitively but unused (no scheduled notifications).
- Debug screen still present (kDebugMode); real Category Manager now supersedes its category bits — left as-is, throwaway.

## How to run

```
flutter pub get
dart run build_runner build      # after any Drift schema change
flutter run                      # pick iOS simulator or Android emulator
flutter analyze && flutter test
```

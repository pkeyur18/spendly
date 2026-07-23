# Spendly — Progress

> Cross-session shared memory. Read this first every session. Update it at the
> end of every sprint before stopping.

## Current status

- **Sprint:** 7 (Polish & Accessibility) — **built, awaiting user verification (real VoiceOver/TalkBack pass, Dynamic Type at largest setting, cold-start stopwatch timing)**
- **Next:** Sprint 8 (Beta & Hardening) — TestFlight/Internal Testing builds, crash reporting + opt-in analytics, a week-long bug bash, edge cases (currency-locale mid-month, date/time changes, cross-version restore, 1000+ transactions).
- **Locked (Sprint 6):** tap-to-add from a widget deep-links into Quick Add (opens the app) rather than writing natively in-widget — see Sprint 6 section below for the full tradeoff.

## Locked decisions (from PRD open questions)

- **Currency:** single currency; symbol + number format follow device locale, default ₹ INR. Multi-currency = v2. (PRD Q1)
- **Recurring (FR-7):** remind + user confirms on due date via local notification; never silent auto-log. (PRD Q3)
- **State management:** Riverpod (`flutter_riverpod`).
- **Local DB:** Drift (SQLite). Money stored as **integer minor units** (paise), never float.
- **Cloud sync (PRD Q2):** share-sheet save only for v1 — no account, no auto-sync, no server. FR-31's account-based sync is out of scope; FR-35 is fully satisfied by the OS share/save sheet.
- **Backup encryption (PRD Q6):** optional password protection (AES-256-GCM + PBKDF2), user's choice per backup — not mandatory, not always-on.
- **Auto-backup default frequency (PRD Q7):** weekly (matches the prototype's pre-selected chip). Daily/monthly also selectable.

## Stack / tooling

- Flutter 3.44.7 (latest stable) · Dart 3.12.2 · Xcode 26.6 · Android SDK · CocoaPods (all verified present).
- Dependency freshness: **all direct deps latest, except where noted below**. Remaining `pub outdated` flags (analyzer 12, meta, test, build_runner, drift_dev, package_config 2, record_use 0.6, …) are **SDK-pinned by Dart 3.12.2** — `Resolvable == Current`, not bumpable without a newer Flutter/Dart. No `dependency_overrides` (would break). Revisit when stable Flutter ships newer Dart.
- Deps: flutter_riverpod, drift + sqlite3_flutter_libs + path_provider + path, intl, fl_chart, **flutter_local_notifications ^22.1.0**, **pdf ^3.13** (S4 export), **flutter_timezone ^5.1** + **timezone ^0.11** (S4, for `zonedSchedule`), **cryptography ^2.9** (S5 — AES-GCM + PBKDF2 for optional backup password), **home_widget ^0.9.3** (S6 — shared-store bridge to iOS WidgetKit / Android Glance). Dev: drift_dev, build_runner, flutter_lints.
- **iOS deployment target is 26.0 (all 6 build configs in `project.pbxproj`) — explicit user override of the PRD's iOS 16+ target, not a technical requirement.** `home_widget`'s CocoaPod only needed 14.0 (that was the S6 fix, done first); the user then explicitly asked to bump further to 26.0 (Apple's current/latest release), fully aware this restricts the whole app to devices already on iOS 26 and excludes iOS 16-25 users entirely — **flagged to the user before applying, confirmed intentional.** If a future session needs to widen the install base again, 14.0 is the real floor (`home_widget`'s minimum); the lock-screen widget code is separately gated `@available(iOS 16.0, *)` in Swift regardless of deployment target.
- **Android Glance widgets need the Compose compiler Gradle plugin** (`org.jetbrains.kotlin.plugin.compose`, pinned to the same version as `org.jetbrains.kotlin.android`, 2.3.20) plus `buildFeatures { compose = true }` and `androidx.glance:glance-appwidget:1.1.1` in `android/app/build.gradle.kts`/`settings.gradle.kts`. Without the compose plugin, Glance's `@Composable` functions fail to compile.
- **share_plus pinned to ^12.0.2 (downgraded from ^13.2 in S4) — deliberate, do not bump casually.** `share_plus ^13.2.1` requires `win32 ^6.0.1`; every `file_picker` version compatible with this project's Android toolchain (see below) requires `win32 ^5.9.0`. The two can't coexist above `share_plus 12.x`. Verified `share_plus 12.0.2`'s `ShareParams`/`SharePlus.instance.share` API is unchanged from 13.x — `report_export.dart`'s `shareReportFile` needed no changes. Re-check this constraint before bumping either package.
- **file_picker pinned to exactly `10.3.10` (not `^`) — deliberate, do not bump to 11.x.** FR-38 restore needs a file picker; `file_picker` 11.0.0+ added an AGP-9-or-above code path in its own `android/build.gradle` that **skips applying the classic `org.jetbrains.kotlin.android` plugin**, assuming the host app's `android.builtInKotlin` gradle property is `true`. This project's `android/gradle.properties` sets `android.builtInKotlin=false` (the Flutter-template default, required because `flutter_local_notifications` applies the classic Kotlin plugin unconditionally and hard-fails under `builtInKotlin=true` — tried it, real build break, not just a warning). Net effect with `file_picker >=11.0.0`: its Kotlin sources never compile (`FilePickerPlugin` class missing) → link error in `GeneratedPluginRegistrant`. `file_picker 10.3.10` still applies the classic Kotlin plugin unconditionally like every other plugin here, so it just works. Also note: 10.3.10's `FilePicker` API is the older instance-based `FilePicker.platform.pickFiles(...)`, not 11.x's static `FilePicker.pickFiles(...)` — `restore_screen.dart` uses the `.platform` form. Re-check this whole situation (ideally by trying 11.x again) once `flutter_local_notifications` ships a Built-in-Kotlin-compatible release.
- **KGP warning (non-blocking):** `flutter_timezone`, `share_plus` (≤12.x), and `file_picker` (10.3.10) all apply the legacy Kotlin Gradle Plugin; APK builds fine but Flutter warns future versions will fail. Watch for releases migrated to Built-in Kotlin, then reconsider `android.builtInKotlin=true` as a set (see above — it's an all-or-nothing flip across every plugin in this project today).
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

## Sprint 4 — done (Reports + export/share + auto monthly report)

Decisions: export via **pdf + share_plus**; CSV hand-written (RFC-4180). Auto month-end report = **scheduled local notification** (`zonedSchedule`, monthly-repeat, no backend); **email = a share-sheet target** (no email backend/secrets). Custom range = native `showDateRangePicker`.

- [x] Report math (FR-20) → pure `lib/features/reports/report_model.dart` (`buildReport` — total, prev-period compare + `changePct`, daily avg, txn count, top category, breakdown, top-5, weekly buckets). Derived from ONE in-range list (`ExpenseRepository.listInRange`) + one prev-period `totalInRange`. Unit-tested.
- [x] Providers → `report_providers.dart` (`reportProvider` FutureProvider.family keyed by `(start,end)`).
- [x] Export/share (FR-21,22,32) → `report_export.dart`: `buildCsv` (pure, tested), `buildPdf` (pdf pkg, renders with bundled Inter/Sora so ₹ shows — Helvetica lacks it), `shareReportFile` (temp file → `SharePlus.instance.share`). One path serves PDF/CSV/email.
- [x] Screens: `monthly_report_screen.dart` (phone 3 — hero, stat grid incl. budget-used %, donut, top-5, export) + `custom_report_screen.dart` (phone 4 — quick chips + `showDateRangePicker`, hero, weekly trend, donut, export). Shared UI in `report_widgets.dart` (ReportHero, StatGrid, TopExpensesCard, ExportRow).
- [x] Chart reuse: extracted provider-free `DonutChart` + `TrendBarsView` from `spend_donut.dart` / `trend_bars.dart`; Home wrappers unchanged.
- [x] Auto report (FR-17,18) → `notifications.dart`: `init()` now sets up timezone db + local zone (flutter_timezone); `scheduleMonthlyReport()` = `zonedSchedule` 1st-of-month 09:00, `matchDateTimeComponents.dayOfMonthAndTime` (monthly repeat, no persisted state), `inexactAllowWhileIdle` (no exact-alarm perm). Tap → `appNavigatorKey` pushes previous month's report. Called in `main()`.
- [x] Nav: Home Reports tab → MonthlyReportScreen(current month). `MaterialApp.navigatorKey = appNavigatorKey`.
- [x] Android: `RECEIVE_BOOT_COMPLETED` + `ScheduledNotificationBootReceiver` (re-arm after reboot).

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **58 passed** (+ report_model 6, report_csv 3).
- `flutter build apk --debug` ✓ · `flutter build ios --debug --simulator --no-codesign` ✓ (new native deps).

### Deferred / notes
- No server push / email backend — auto delivery = on-device scheduled notification; "email" = share-sheet target. Server-triggered push / backend-mailed PDF = separate infra track.
- Monthly notification body is fixed text ("report ready"), month resolved at tap time — required because `matchDateTimeComponents` can't vary text per fire. Inexact firing (dodges SCHEDULE_EXACT_ALARM).
- PDF is a functional summary, not a pixel-match of prototype cards (prototype has no PDF design).
- Comparison = immediately-preceding same-length window only.
- Reports load all in-range expenses into memory (on-demand, fine); `listInRange` added for this.

## Sprint 5 — done (Backup, Export & Import)

Decisions locked with the user before starting (see "Locked decisions" above): share-sheet-only cloud save, optional password protection via `cryptography` (AES-256-GCM + PBKDF2), weekly default auto-backup frequency, `file_picker` added for restore's file selection (pinned to 10.3.10 — see "Stack / tooling" above for why). Full format spec: `docs/backup-schema.md`.

- [x] Versioned JSON backup format (FR-34) → `docs/backup-schema.md` + `lib/features/backup/backup_models.dart` (DTOs), `backup_format.dart` (envelope encode/decode + validation). Outer envelope (`spendlyBackup`/`version`/`encrypted`) is always plaintext so an incompatible-future-version file is rejected *before* a password is ever requested. `amountMinor` round-trips as an integer, never a float.
- [x] Optional password protection (PRD Q6) → `backup_crypto.dart`: PBKDF2-HMAC-SHA256 (200k iterations) derives an AES-256-GCM key from the password; salt/nonce/mac/ciphertext travel in the envelope. Wrong password / tampered ciphertext both surface as `BackupWrongPasswordException` (GCM tag check), distinct from a generic corrupt-file error.
- [x] Full backup export (FR-33) → `backup_repository.dart` `exportAll()` reads all 4 Drift tables directly via `AppDatabase`'s generated table getters (no changes needed to the existing category/expense/budget repositories — they're scoped to their own CRUD, not bulk export). Settings export excludes the app's own backup-bookkeeping keys (`auto_backup_enabled`, `auto_backup_frequency`, `last_backup_at`, `last_backup_size`) so restoring a file never rewrites the restoring device's own schedule/status.
- [x] Save-to-cloud via share sheet (FR-35) → `backup_export.dart` `shareBackupFile()` reuses `report_export.dart`'s `shareReportFile()` verbatim (same temp-file + `SharePlus.instance.share` pattern Sprint 4 built) — no duplicated share logic.
- [x] Manual "Back up now" (FR-36) + Settings screen → `lib/features/settings/settings_screen.dart` (replaces the Sprint-4 stub; theme row + Backup & Restore tile) and `lib/features/backup/backup_restore_screen.dart` (prototype phone 9): status card, auto-backup toggle + Daily/Weekly/Monthly chips, "Back up now" (optional password dialog) + "Restore from a backup file", what's-included card.
- [x] Auto-backup scheduler (FR-37) → `local_auto_backup.dart` `runAutoBackupIfDue()`. **Deliberate deviation, flagged to the user and approved:** no background-execution package exists in this project and adding one (`workmanager`/`android_alarm_manager_plus`) is heavy/flaky cross-platform for a weekly cadence, so the due-check runs on **app launch/resume** instead (`app.dart`'s `WidgetsBindingObserver`, invalidating `autoBackupCheckProvider` on `AppLifecycleState.resumed`) — satisfies user-facing FR-37 for an app opened at least as often as its own cadence, but isn't a true OS-scheduled background job. Auto-backups are never password-protected (nobody's present to type one) and only write a local file at `<applicationSupportDirectory>/backups/spendly-backup-latest.json` (single file, overwritten each run, no rotation) — they do **not** open the share sheet; only manual "Back up now" delivers to cloud storage, since that hand-off is inherently an interactive OS action.
- [x] "Last backup" status (FR-42) → `backup_providers.dart` `lastBackupStatusProvider` reads timestamp + size from Settings, shown in the status card.
- [x] Restore flow (FR-38, FR-39, FR-40) → `backup_import.dart` (`loadAndValidate` → preview, `executeRestore` → dispatch) + `restore_screen.dart` (prototype phone 10): file picker → preview card (date, expense count, date range, file size) → Merge/Replace radio choice → restore. Password-required/wrong-password both re-prompt inline without re-picking the file.
- [x] Merge algorithm — natural-key matching, **no schema change** (`backup_repository.dart` `mergeAll`): categories matched by normalized name (stops the 8 seeded defaults from doubling), expenses matched by content fingerprint (amount/date/mapped-category/note/payment-method), budgets matched by mapped-category slot. Deliberately rejected adding a UUID column — the only in-scope cross-device scenario is a one-time restore onto an empty/near-empty device, not continuous multi-device sync (out of scope per the Q2 decision), so a migration for it wasn't justified. **Known ceiling, documented in `docs/backup-schema.md`:** renaming a category between backup and restore breaks name-matching (inserts a "new" one instead of recognizing the rename); fingerprint matching can rarely collide two distinct expenses sharing amount+date+category+note+payment-method. Upgrade path: nullable `externalId` UUID column via a real migration, if this ever bites.
- [x] Replace algorithm (`replaceAll`) — wipes all 4 tables (child-to-parent FK order) then restores the backup verbatim (original ids reused, safe since tables are empty), all inside one `db.transaction` — any failure rolls back automatically.
- [x] Backup file validation (FR-41) → `backup_format.dart`'s `decodePayload` is the single gate: corrupt JSON, missing `spendlyBackup` marker, incompatible future `version`, wrong/missing password all throw distinct typed exceptions *before* any DB write is attempted — verified by a repository test that a corrupted-file import leaves all existing rows untouched.

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **74 passed** (+ backup_format 7, backup_repository 6, backup_crypto 3).
- `flutter build apk --debug` ✓ · `flutter build ios --debug --simulator --no-codesign` ✓ (new native deps — see the file_picker/share_plus pin notes above; this took real back-and-forth, don't casually bump either without re-reading those notes first).

### Deferred / notes
- Manual verification (uninstall/reinstall/restore, both Merge and Replace, password-protected backup, auto-backup firing on resume, corrupted-file import) not yet run on a real simulator/emulator by the user — see the steps in the plan file / ask for the walkthrough.
- Currency/notification rows deliberately not stubbed in the new Settings screen — not assigned a sprint yet.
- `android/gradle.properties`' `android.builtInKotlin` flag was tried at `true` to fix file_picker, then reverted — it breaks `flutter_local_notifications` outright (real error, not just the deprecation warning). Left at `false`; see the file_picker pin note above.

## Sprint 6 — done (Home Screen + Lock Screen Widgets)

**Locked decision, approved by the user before starting:** tap-to-add from a widget (FR-3) deep-links into the app's Quick Add screen with the category preselected, rather than writing the expense natively from inside the widget. **This means FR-3/FR-27's "add without opening the app" is not literally met** — tapping a quick-add category opens the app on Quick Add, prefilled, one tap from saved. The read-only display widgets (today total, month total, budget bar, trend, lock screen) *do* update without opening the app, satisfying FR-29. True no-open writes would need iOS 17 App Intents + app-side reconciliation logic, deliberately skipped as bigger scope than this sprint needs. Platforms were built iOS-first then Android, per plan; all four widget variants (FR-26 small today+trend, FR-27 small quick-add, FR-28 medium combo, FR-4 iOS lock screen) were built in this one pass rather than staged.

- [x] Shared snapshot layer (serves both platforms) → `lib/features/widgets/widget_snapshot.dart`: pure `buildWidgetSnapshot(...)` (today/month totals, budget %/left — integer-exact, clamped so an over-budget month never goes negative or over 100 — 6-month trend as 0-100 relative bar heights, up to 4 quick-add categories with last-used first) + `WidgetBridge` (thin wrapper over `home_widget`: `saveWidgetData` per key, then reloads every iOS widget kind and the Android receiver). `lib/features/widgets/widget_refresh.dart` `refreshWidgets(ref)` is the one function every hook site calls — reads live data from the existing repositories/providers (no new query engine beyond the two net-new bits below) and pushes a fresh snapshot.
- [x] Two net-new queries → `expense_repository.dart`: `dayBounds()` (mirrors the existing `monthBounds`) + `todayTotal()` (FR-26 "today's total" didn't exist before this sprint). Budget "% used" also didn't exist precomputed — it's derived in `buildWidgetSnapshot` from `overallBudgetProvider` + month total, same integer math pattern as the home dashboard's budget bar.
- [x] Refresh hooks (FR-29 — "refresh after any new expense, from any source") → `quick_add_screen.dart` `_save()` (right after the existing budget-alert check), `app.dart` cold-start (`addPostFrameCallback`) and `AppLifecycleState.resumed` (same lifecycle observer Sprint 5's auto-backup check already uses), and `restore_screen.dart` after a successful restore. Cold-start/resume is the catch-all for anything that doesn't route through Quick Add.
- [x] Deep-link tap-to-add (FR-3, as scoped above) → `quick_add_screen.dart` gained an `initialCategoryId` constructor param (only applied when not editing — `_applyDefaultCategory` already early-returns once `_categoryId` is set, so no conflict with last-used preselection). `app.dart` listens to `HomeWidget.widgetClicked` + checks `HomeWidget.initiallyLaunchedFromHomeWidget()` on `initState`, parses `spendly://quickadd?category=<id>`, and pushes `QuickAddScreen` via the existing `appNavigatorKey`.
- [x] **iOS** (`ios/SpendlyWidget/`) → `SpendlyWidget.swift`: one `WidgetBundle` with 4 `Widget`s (`SpendlyTodayWidget` `.systemSmall`, `SpendlyQuickAddWidget` `.systemSmall` with `Link`-based category buttons, `SpendlyMonthWidget` `.systemMedium` combo, `SpendlyLockWidget` `.accessoryRectangular`/`.accessoryInline` gated `@available(iOS 16.0, *)`). A single `TimelineProvider` reads the snapshot from `UserDefaults(suiteName: "group.com.spendly.spendly")` — decoding is defensive (missing keys → safe zero/placeholder strings, never a crash). `containerBackgroundCompat` shims the iOS-17-required `.containerBackground(for:.widget)` API so the same view code runs on 14/15/16 too.
- [x] **Android** (`android/app/src/main/kotlin/com/spendly/spendly/widget/`) → `SpendlyGlanceWidget` (one responsive Glance composable reading `HomeWidgetGlanceState.preferences` — Android widgets are natively resizable, so one adaptive layout replaces iOS's 3 fixed sizes) + `SpendlyWidgetReceiver` (`HomeWidgetGlanceWidgetReceiver<SpendlyGlanceWidget>`). Registered via `res/xml/spendly_widget_info.xml` + a manifest `<receiver>` entry. No Android lock-screen equivalent — FR-4 is iOS-only, matches the prototype.
- [x] Unit tests → `test/widget_snapshot_test.dart` (6 tests): today/month totals stay distinct, budget % is integer-exact and clamps (never negative, never >100), no-budget case, 6-bar trend relative-height math including the flat-trend (all-zero, no divide-by-zero) case, quick-add caps at 4 and carries id/icon/name through JSON.

### The iOS extension target — the fragile step, and how it was actually done
No Xcode GUI is available in this environment, so "Add Target → Widget Extension" (the normal path) wasn't an option. Instead: wrote the Swift/Info.plist/entitlements files by hand, then used the `xcodeproj` Ruby gem (bundled with the already-installed CocoaPods toolchain — verified present before relying on it) to script the `PBXNativeTarget` creation, entitlements wiring, and embed-phase setup (script kept at the session's scratchpad, not committed — it's a one-time setup tool, not part of the app). **Backed up `project.pbxproj` before running it.** Three real build errors surfaced and were fixed in order, each worth knowing about if this target is ever touched again:
1. `home_widget`'s CocoaPod requires iOS 14 minimum — bumped all 6 `IPHONEOS_DEPLOYMENT_TARGET` entries (Runner + RunnerTests + SpendlyWidget, debug/release/profile) from 13.0 to 14.0. (Later bumped again to 26.0 at the user's explicit request — see "Stack / tooling" above; that second bump is a scope decision, not part of this fragile-step fix.)
2. `PRODUCT_NAME` was unset on the new target, so the build emitted a nameless `.appex` while the product reference expected `SpendlyWidget.appex` → "Multiple commands produce" error. Fixed by setting `PRODUCT_NAME = $(TARGET_NAME)` on the extension's build configs.
3. A dependency cycle: the scripted "Embed App Extensions" copy-files phase landed *after* Flutter's own "Thin Binary" script phase in the phase list, which the Thin Binary script's Info.plist processing indirectly depended on. Fixed by reordering the phase list so "Embed App Extensions" runs immediately before "Thin Binary" (`Run Script → Sources → Frameworks → Resources → Embed Frameworks → Embed App Extensions → Thin Binary`).

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **80 passed** (+ widget_snapshot 6).
- `flutter build apk --debug` ✓ (Glance resources confirmed packaged in the APK via `unzip -l`) · `flutter build ios --debug --simulator --no-codesign` ✓ (widget `.appex` confirmed embedded in `Runner.app/PlugIns/`), re-verified after the Android Gradle changes too.

### Deferred / notes — real manual verification NOT yet done, needs the user
- **This is build-level verification only.** Nobody has yet: placed any widget on a real iOS simulator or Android emulator home screen, confirmed it renders live data, tapped a quick-add category and confirmed Quick Add opens with that category preselected, saved an expense and confirmed the widget updates on next resume, or checked the lock-screen widget on an iOS 16+ simulator. This is exactly the sprint the plan warned would have "platform-specific surprises" — treat the build success as necessary, not sufficient. See the plan file's Verification section for the full walkthrough steps.
- Widget snapshot money strings are pre-formatted by the Dart side (`Money.format(locale: 'en_IN')`) — the native widgets never do currency math, only display strings. If multi-currency ever lands (v2), this is the one spot that assumes a fixed locale.
- iOS widget refresh timeline policy is `.after(1 hour)` as a safety net; the real refresh path is always the explicit `reloadTimelines` call from `refreshWidgets`, not the timeline's own schedule.
- No `home_widget`-specific KGP conflict surfaced (it resolved and built cleanly on both platforms), but it does apply the legacy Kotlin plugin like the others already tracked above.

## Sprint 7 — done (Polish & Accessibility)

Two read-only audits (screen-reader/Dynamic Type/color-blind gaps, and cold-start/animation) ran first to find concrete, file-level gaps before writing any code — this sprint fixes exactly those, nothing speculative. No prototype redesign; the NFR checklist (PRD §6) is the spec.

- [x] **Screen-reader labels (VoiceOver/TalkBack)** — zero `Semantics`/`Tooltip` existed anywhere before this sprint. Added `tooltip:` to the bottom-nav icons, FAB, and Quick Add's close button (`home_screen.dart`, `quick_add_screen.dart`); wrapped every custom `GestureDetector`/`InkWell` tappable with no visible-only-icon label in `Semantics(button: true, label: ...)` — keypad keys and "Set budget" (`amount_keypad.dart`), category tiles and Save (`quick_add_screen.dart`), icon/color swatches and Save (`category_edit_sheet.dart`), settings tiles (`settings_screen.dart`), frequency chips and both CTA buttons (`backup_restore_screen.dart`), the file-picker tile and Merge/Replace cards (`restore_screen.dart`), the "+ Set budget" button (`budget_setup_screen.dart`), and the reusable `AppCard`/`SectionTitle` action link (`app_card.dart`). `dev/debug_data_screen.dart` (kDebugMode-only, not shipped) was deliberately skipped.
- [x] **Chart accessibility** — fl_chart draws to canvas and exposes nothing to a screen reader on its own. Added one `Semantics(label: <summary>)` wrapper per chart with a pure, unit-tested label builder: `donutSemanticsLabel` (`spend_donut.dart`) and `trendSemanticsLabel` (`trend_bars.dart`), each summarizing the whole chart in one sentence ("Category breakdown, total ₹X: Food 40 percent, ..."). **Documented ceiling:** per-slice/per-bar semantics wasn't built — one summary label per chart is the standard, proportionate fix for fl_chart; the underlying `PieChart`/`BarChart` canvases are wrapped in `ExcludeSemantics` so a screen reader doesn't also try (and fail) to read the raw canvas nodes.
- [x] **Dynamic Type** — no blocking override existed before this sprint (`Text` already honors system font scaling by default); the real risk was fixed-size containers that can't reflow. Fixed: `AmountDisplay`'s `RichText` now passes `textScaler: MediaQuery.textScalerOf(context)` explicitly (`RichText` doesn't auto-inherit the ambient scaler the way `Text` does — the actual bug). The donut (`spend_donut.dart`) and trend chart (`trend_bars.dart`) each locally clamp their internal `MediaQuery.textScaler` to a **1.3x max** via a `MediaQuery(data: ...copyWith(textScaler: ...clamp(maxScaleFactor: 1.3)))` wrapper — a bounded, documented ceiling scoped to just those two fixed-size chart widgets; everything else in the app scales uncapped. The home-screen logo badge (`home_screen.dart`) swapped its fixed `Container` + raw `Text` for a `FittedBox`-wrapped glyph so it shrinks instead of clipping.
- [x] **Color-blind safety** — 3 concrete color-only gaps fixed with minimal, non-redesign additions: the trend chart's "current month" bar (`trend_bars.dart`) now also bold-weights its axis label (`FontWeight.w800` vs `w400`) instead of relying on the orange-vs-purple gradient alone; Quick Add's selected category tile (`quick_add_screen.dart` `_CategoryTile`) gained a small `Icons.check_circle` badge overlay; the category icon picker (`category_edit_sheet.dart`) gained the same checkmark-badge treatment, and the color picker swatch now shows a contrast-aware `Icons.check` glyph (black or white depending on `computeLuminance()`) instead of only an outline ring. The budget usage bar and donut legend already paired color with a text label — left unchanged. Raw `PieChart` slice-vs-slice distinction (no per-slice pattern) is an accepted, documented ceiling — the chart's own `Semantics` summary label already carries that information non-visually, and per-slice patterns aren't practical with fl_chart.
- [x] **Empty / error / loading states** — added one shared `lib/core/widgets/async_state_views.dart` (`LoadingView`, `ErrorView(message, onRetry)`, `EmptyView(icon, message)`), justified by reuse across 8+ screens (not a single-use abstraction). Converted `budget_setup_screen.dart`, `settings_screen.dart`, and `backup_restore_screen.dart` from reading `AsyncValue.value` directly (silently showing stale/null data and swallowing errors, no spinner) to routing through explicit loading/error branches. Replaced every screen's raw, unstyled `Text('Error: $e')` branch (`category_manager_screen.dart`, `quick_add_screen.dart`, `monthly_report_screen.dart`, `custom_report_screen.dart`) with `ErrorView` + a retry action that invalidates the relevant provider. Added a real empty-state branch where one was genuinely missing: zero categories (`category_manager_screen.dart`), zero transactions in the report period (`monthly_report_screen.dart`, `custom_report_screen.dart`). `home_screen.dart`'s existing recent-transactions empty state and `restore_screen.dart`'s inline (non-`AsyncValue`-driven) error text were left as-is — already reasonable, not provider-`.value` bypasses.
- [x] **Performance: cold start & widget tap-to-save (NFR: <2s / <1s)** — `main.dart` previously **awaited** `notifications.init()` then `scheduleMonthlyReport()` before `runApp()`; each does platform-channel round trips (timezone lookup, plugin registration, a possible OS permission prompt, a `zonedSchedule` call), and since a widget tap cold-starts the whole app through this same sequence before `QuickAddScreen` can appear, it gated both budgets identically. Fix: `main()` now calls `runApp()` immediately after `WidgetsFlutterBinding.ensureInitialized()`; both calls moved to `app.dart`'s existing post-first-frame hook (same `addPostFrameCallback` Sprint 6 added for `refreshWidgets`), fired un-awaited. **Accepted risk:** a notification tap arriving in the few-hundred-ms window before `init()` completes could be missed — vanishingly unlikely (requires an already-fired local notification at the exact instant of launch) and not worth blocking the first frame for. The Drift DB-open path was already lazy/backgrounded (`LazyDatabase` + `NativeDatabase.createInBackground`) — confirmed not a bottleneck, no change needed.
- [x] **Animation pass (scoped)** — the prototype (`spendly-prototype.html:48`) specifies exactly one motion rule: a `.4s ease` background/color crossfade on theme toggle; nothing else (no hover/press feedback, no chart/bar entrance animation, no page transitions) was designed. Added `AnimatedTheme` (400ms, `Curves.ease`) around `MaterialApp`'s `builder` in `app.dart` so switching system/light/dark crossfades colors instead of snapping. **Deliberately did not** add motion anywhere else — per the sprint's own instruction ("only where the prototype's motion was intentional, nothing gratuitous"), tuning fl_chart's entrance animation or adding a budget-bar fill tween would be gratuitous, since neither was in the original design.
- [x] Unit tests → `test/chart_semantics_test.dart` (5 tests): `donutSemanticsLabel` (empty case, per-slice percent summary, caps at 5 slices) and `trendSemanticsLabel` (empty case, flags the current month without over-flagging others).

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **85 passed** (+ chart_semantics 5).
- `flutter build apk --debug` ✓ (KGP warning unchanged from Sprint 6 — pre-existing, tracked above, not a regression) · `flutter build ios --debug --simulator --no-codesign` ✓.

### Deferred / notes — real manual verification NOT yet done, needs the user
- **This is build-level verification only**, same caveat as Sprint 6. Nobody has yet: run a real VoiceOver (iOS) or TalkBack (Android) pass through every screen; set Dynamic Type to its largest accessibility setting and confirmed no clipped/overlapping text (especially the two chart widgets' 1.3x-clamped labels and the keypad); stopwatch-timed a real cold start or a real widget-tap-to-QuickAddScreen open on a device/simulator. Treat the build/analyze/test green as necessary, not sufficient — this is exactly the kind of gap that only shows up interactively.
- The 1.3x textScaler clamp inside `spend_donut.dart`/`trend_bars.dart` is a deliberate, bounded ceiling — if it ever feels too restrictive, the fix is to raise `maxScaleFactor` there, not to remove the clamp (the charts' fixed pixel dimensions can't reflow like a list).
- `AppCard`'s `InkWell`-based `onTap` now carries `Semantics(button: true)` but no explicit `label:` — its callers already surround it with descriptive visible text (e.g. a transaction's title + amount), so screen readers get that context from the descendant text nodes rather than a hand-written label. If a future `AppCard` caller has no descendant text, it should pass its own `Semantics(label:)` wrapper rather than relying on this.

## How to run

```
flutter pub get
dart run build_runner build      # after any Drift schema change
flutter run                      # pick iOS simulator or Android emulator
flutter analyze && flutter test
```

# Spendly — Progress

> Cross-session shared memory. Read this first every session. Update it at the
> end of every sprint before stopping.

## Current status

- **Sprint:** 5 (Backup, Export & Import) — **built, awaiting user verification**
- **Next:** Sprint 6 (Widgets — Home Screen + Lock Screen, `home_widget` package + native Swift/Kotlin). Budget extra time per the sprint plan; most likely sprint to have platform-specific surprises.

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
- Deps: flutter_riverpod, drift + sqlite3_flutter_libs + path_provider + path, intl, fl_chart, **flutter_local_notifications ^22.1.0**, **pdf ^3.13** (S4 export), **flutter_timezone ^5.1** + **timezone ^0.11** (S4, for `zonedSchedule`), **cryptography ^2.9** (S5 — AES-GCM + PBKDF2 for optional backup password). Dev: drift_dev, build_runner, flutter_lints.
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

## How to run

```
flutter pub get
dart run build_runner build      # after any Drift schema change
flutter run                      # pick iOS simulator or Android emulator
flutter analyze && flutter test
```

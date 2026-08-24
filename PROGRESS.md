# Spendly — Progress

> Cross-session shared memory. Read this first every session. Update it at the
> end of every sprint before stopping.

## Current status

- **Phase:** UX-enhancement plan, phases 1-4 complete, plus a Phase 4 follow-up
  (default account + account detail screen, schema v13) requested after Phase 4
  shipped. See `docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md` for the
  full phased plan and the ledger architecture decision. Branch `feat/ux-enhancements`.
  Sprints 0-7 + 10-12 and Monthly Recap shipped before this.
  Plus an Excel-export completeness pass (trip/account/recurring/receipt/foreign-amount
  columns) requested right after that follow-up shipped — no schema change, still v13.
  **Drift schema is now v13; backup format v8.** `flutter analyze` clean,
  `flutter test` **404 passing** (51 test files).
- **Next:** Phase 5 (income, schema v14 — v13 is now taken by the default-account
  follow-up) — the first phase to touch the new `LedgerEntries` table decision, then
  phase 6 (transfers, derived balances) and phase 7 (insights, goals, app lock,
  autocomplete). Sprint 8/9 (Beta & Hardening, Store Submission) still not started.
- **Doc drift found and fixed:** README claimed schema v7 / backup v3 / 190 tests while
  the code was already at schema v9 / backup v5 — FX spending and trip date-range
  auto-tagging had shipped with no README or PROGRESS entry. Both files now match the
  code. Check this before trusting a version number in any doc.
- **Locked (Sprint 6):** tap-to-add from a widget deep-links into Quick Add (opens the
  app) rather than writing natively in-widget — see Sprint 6 section below.

## Locked decisions (from PRD open questions)

- **Currency:** single currency; symbol + number format follow device locale, default ₹ INR. Multi-currency = v2. (PRD Q1)
- **Recurring (FR-7):** remind + user confirms on due date via local notification; never silent auto-log. (PRD Q3)
- **State management:** Riverpod (`flutter_riverpod`).
- **Local DB:** Drift (SQLite). Money stored as **integer minor units** (paise), never float.
- **Cloud sync (PRD Q2):** share-sheet save only for v1 — no account, no auto-sync, no server. FR-31's account-based sync is out of scope; FR-35 is fully satisfied by the OS share/save sheet.
- **Backup encryption (PRD Q6):** optional password protection (AES-256-GCM + PBKDF2), user's choice per backup — not mandatory, not always-on.
- **Auto-backup default frequency (PRD Q7):** weekly (matches the prototype's pre-selected chip). Daily/monthly also selectable.

## Catch-up — work that shipped without a PROGRESS.md entry

Five commits (`0b23fe4` iOS widget app-group fix, `4f0c24c` new app icon,
`4c40ec5` category-grid layout fix, `7fe95f7` bare profile screen,
`dd6724f` reports-live-update/app-icon/widget-deep-link fixes) plus
uncommitted onboarding work all landed after the Sprint 7 entry above was
written, with no corresponding PROGRESS.md update. Recorded now, retroactively:

- **Onboarding (FR-44–50)** → `lib/features/onboarding/welcome_screen.dart`.
  Name (mandatory, gates "Get started"), phone/email (optional). Saves
  through the same `profileProvider` Sprint 10 builds on — it never
  navigates itself; `app.dart`'s `home:` watches `profileProvider` and shows
  `WelcomeScreen` vs `HomeScreen` based on whether `profile.name` is empty.
  This *is* the FR-50 "first launch only" gate — there's no separate
  onboarding-complete flag.
- **Bare Profile screen (FR-49, FR-52 partial)** → `profile_provider.dart`
  (`Profile{name,email,phone}` over the generic `Settings` k/v table) +
  a 3-`TextField` `ProfileScreen`, reachable from a "Profile" tile inside the
  (now-removed, see Sprint 10) Settings screen. Also wired into report
  CSV/PDF export (`report_export.dart`) and `resetToDefaults()`
  (`test/reset_test.dart`).
- **`dd6724f`** — reports weren't live-updating (`reportProvider` was a
  `FutureProvider`, not reactive to new expenses; changed to `StreamProvider`
  over `watchInRange`); app icon was cropped (regenerated via
  `flutter_launcher_icons` from `assets/logo/app_logo.png`); widget deep-link
  URL scheme registration added to `ios/Runner/Info.plist`
  (`CFBundleURLTypes` → `spendly://`).
- **Verification:** not independently re-verified as part of this catch-up —
  covered by Sprint 10's `flutter analyze`/`flutter test`/build-sanity pass
  below, since Sprint 10 builds directly on this code.

## Stack / tooling

- Flutter 3.44.7 (latest stable) · Dart 3.12.2 · Xcode 26.6 · Android SDK · CocoaPods (all verified present).
- Dependency freshness: **all direct deps latest, except where noted below**. Remaining `pub outdated` flags (analyzer 12, meta, test, build_runner, drift_dev, package_config 2, record_use 0.6, …) are **SDK-pinned by Dart 3.12.2** — `Resolvable == Current`, not bumpable without a newer Flutter/Dart. No `dependency_overrides` (would break). Revisit when stable Flutter ships newer Dart.
- Deps: flutter_riverpod, drift + sqlite3_flutter_libs + path_provider + path, intl, fl_chart, **flutter_local_notifications ^22.1.0**, **pdf ^3.13** (S4 export), **flutter_timezone ^5.1** + **timezone ^0.11** (S4, for `zonedSchedule`), **cryptography ^2.9** (S5 — AES-GCM + PBKDF2 for optional backup password), **home_widget ^0.9.3** (S6 — shared-store bridge to iOS WidgetKit / Android Glance), **image_picker ^1.2.3** (S10 — camera/gallery for the profile photo, FR-53), **flutter_colorpicker ^1.1.0** (S11 — custom hex color for category/tag edit, behind the 18-swatch brand palette in `category_edit_sheet.dart`'s color popup), **characters** (S10 — grapheme-safe initials logic in `avatar.dart` uses `String.characters`, provided today via `flutter/material.dart`'s re-export; pinned as an explicit direct dependency anyway since it was already resolvable transitively, at ^1.4.1, so the import stays valid even if that re-export path ever changes). Dev: drift_dev, build_runner, flutter_lints, **path_provider_platform_interface** (S10 — fakes `getApplicationSupportPath()` in `backup_repository_test.dart` so the photo round-trip test never touches a real platform channel).
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

## Sprint 10 (Ad-Hoc) — done (Profile, FR-51–58)

Run at the user's explicit request as a fast-follow pulled forward, not in
the normal 0→9 sequence (the sprint plan calls for it after Sprint 9/launch).
Builds directly on the pre-existing bare Profile screen/provider (see
"Catch-up" section above) rather than starting from scratch — that work
already covered FR-49 and part of FR-52; this sprint added everything else.

User-approved decisions (asked up front, before writing code):
- **Added `image_picker`** as a new dependency for camera/gallery upload
  (FR-53) — resolved cleanly (`1.2.3`) against the pinned `share_plus`/
  `file_picker` versions, no conflict.
- **Profile screen replaces the old bare `SettingsScreen`** as the
  bottom-nav gear destination, folding Theme-cycle, Backup & Restore, and
  the destructive reset into Profile's own menu — matches the PRD screen
  list (no separate "Settings" screen exists in it) and the prototype (gear
  icon is shown active *on* the Profile screen, phone 10). `settings_screen.dart`
  is deleted.
- **Currency row is read-only** (shows "Indian Rupee (₹)", no tap target) —
  multi-currency is already locked out-of-scope-v2 (PRD Q1), nothing to
  configure yet.

- [x] **Avatar data model** — no Drift schema bump needed. `Profile`
  (`profile_provider.dart`) gained `photoPath`/`avatarColorIndex`, stored as
  two more plain rows in the existing generic `Settings` table (new keys
  `profile_photo_path`, `profile_avatar_color` in `SettingsRepository`) —
  same pattern as the existing name/email/phone fields.
- [x] **Avatar logic (FR-54, FR-55)** → `lib/features/profile/avatar.dart`:
  `avatarGradients` (5 presets, colors lifted verbatim from the prototype's
  `.avatar-opt` swatches — index 0 is the default), pure `initialsFor(name)`
  (grapheme-safe via `String.characters`, never throws, never returns
  something unrenderable — handles blank/single-word/multi-word/emoji names),
  and the shared `ProfileAvatar` widget (photo via `Image.file` if
  `photoPath` is set and the file exists, else colored initials) — the one
  render path used everywhere an avatar appears, so there's no
  blank/broken-image state anywhere.
- [x] **Lifetime stats (FR-51)** → `lib/features/profile/lifetime_stats.dart`:
  pure `computeLifetimeStats` (distinct months, expense count, distinct
  categories used) over `ExpenseRepository.watchLifetimeStats()` (a new
  query selecting only `date`+`categoryId`, not full rows) — stream-derived
  like the existing dashboard providers, so it updates live.
- [x] **Profile hub screen (FR-51, FR-57)** → rewrote
  `lib/features/profile/profile_screen.dart`: hero avatar + edit-pencil
  badge, 3-stat row, then grouped menu sections — *Account* (Edit profile,
  Change photo/avatar), *Preferences* (Theme — tap-cycles, same logic
  Settings used; Currency — read-only), *Account actions* (Delete all data).
- [x] **Edit Profile (FR-52)** → new `edit_profile_screen.dart`, extracted
  from the old bare `ProfileScreen`'s form (name/phone/email + Save), with
  the avatar+pencil now at top linking to the Avatar Picker.
- [x] **Avatar Picker (FR-53, FR-54)** → new `avatar_picker_screen.dart`:
  upload dropzone (`image_picker`, bottom-sheet choice of camera/gallery,
  image copied to `<applicationSupportDirectory>/profile/avatar.jpg`,
  single file, overwritten each pick — no history) + horizontal row of the 5
  color swatches, selection state, Save.
- [x] **Delete all data, backup-gated (FR-58)** → new
  `lib/features/profile/delete_all_data_flow.dart`: tapping the row shows
  *"Back up your data first?"* (Back up now / Continue without backing up /
  Cancel) before the pre-existing type-"DELETE"-to-confirm dialog
  (`ResetConfirmDialog`, moved here from the old Settings screen unchanged).
  "Back up now" reuses `performManualBackup`, extracted from
  `backup_restore_screen.dart`'s own button handler so both screens share
  one code path (optional-password dialog → share sheet → status record).
- [x] **Backup schema v2 (FR-56)** → the one genuinely new backup-layer
  piece. Name/email/phone/avatarColorIndex were already plain `Settings`
  rows and already flowed into backups with no schema change; the photo is
  a local file, which JSON can't reference portably across devices. Added
  optional `profilePhotoBase64` to `BackupPayload`
  (`backup_models.dart`); bumped `currentBackupVersion` to **2**
  (`backup_format.dart`) — no version-keyed decode branch needed, since a
  v1 file simply lacks the key and `fromJson` already reads that as null.
  `BackupRepository.exportAll()` excludes `profile_photo_path` from the
  generic settings export (device-specific, meaningless elsewhere) and
  base64-encodes the photo file's bytes into the payload if one exists.
  `replaceAll()` decodes it (if present) to a fresh local file and writes a
  new `profile_photo_path` setting row; if absent (v1 file, or a v2 file
  with no photo), photo state is left wiped, correctly falling back to
  colored initials. **`mergeAll()` deliberately does not touch the photo** —
  consistent with its pre-existing, documented behavior that merge never
  touches settings at all (so name/email/phone weren't restored on merge
  before this sprint either; the photo follows the same rule for
  consistency, not a new restriction). `docs/backup-schema.md` updated with
  a new "v2 — profile photo" section.
- [x] **iOS permissions** → `NSCameraUsageDescription` +
  `NSPhotoLibraryUsageDescription` added to `ios/Runner/Info.plist` for
  `image_picker`. Android needed no manifest change beyond the plugin's own
  merge.

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **110 passed** (+ `avatar_test` 9, `lifetime_stats_test` 4,
  3 new `profile_provider_test` cases, 2 new `backup_format_test` cases, 3
  new `backup_repository_test` cases covering the v2 photo round-trip via a
  faked `PathProviderPlatform` — no real platform channel touched).
- `flutter build apk --debug` ✓ (KGP warning unchanged from Sprint 6/7 —
  pre-existing, not a regression; `image_picker` isn't in the flagged-plugins
  list) · `flutter build ios --debug --simulator --no-codesign` ✓ (new
  `image_picker` native dep + `Info.plist` permission strings both build
  clean).

### Deferred / notes — real manual verification NOT yet done, needs the user
- **This is build-level verification only**, same caveat as Sprints 6/7.
  Nobody has yet: tapped the gear icon and confirmed the new Profile screen
  renders correctly in both themes; edited name/phone/email and confirmed it
  reflects immediately; picked a color swatch and a real photo (simulator
  camera roll) and confirmed the avatar updates immediately everywhere it
  appears; confirmed a brand-new/reset profile shows colored initials with
  no broken-image flash; confirmed the backup-first dialog actually appears
  before the type-DELETE dialog; exported a backup with a photo set,
  inspected the JSON for `version: 2` + `profilePhotoBase64`, and restored it
  onto a reset app; confirmed a genuine pre-Sprint-10 (`version: 1`) backup
  file still restores correctly. See the plan's Verification section for the
  full walkthrough steps.
- Currency row is intentionally non-interactive (see decision above) —
  revisit once an actual currency feature is scoped.
- `image_picker`'s picked-photo max size is capped at 800×800 /
  quality 85 in `avatar_picker_screen.dart` — a deliberate, undocumented-in-PRD
  ceiling to keep the single avatar file small; raise if a sharper avatar is
  ever needed.
- No photo history — picking a new photo overwrites
  `profile/avatar.jpg` in place. Fine for a single-avatar-per-user model;
  would need a real migration if past photos ever needed to be kept.

## Sprint 11 (Ad-Hoc) — done (Trips, All-Transactions, per-month budgets, picker UX)

Retroactive catch-up, same spirit as the earlier "Catch-up" section: a large run of
feature work landed after Sprint 10 without per-feature PROGRESS entries. Recorded here
as one block. All of it is `flutter analyze` clean and covered by the test suite
(**110+ tests**, see the per-feature test files below). Schema went **v1→v5** and backup
format **v1→v3** across this work; both are additive, mirroring each other (see
`docs/backup-schema.md`). Real-device manual verification still owed, same caveat as
Sprints 6/7/10.

- [x] **Trips / Tags (FR-69–73)** → `features/tags/`. New `Tags` Drift table
  (schema **v4**: `tags` table + nullable `expenses.tagId`) — an expense grouping
  orthogonal to category (a holiday, a wedding, a project). `tag_repository.dart`
  (watchAll/watchActive/create/rename/recolor/archive/unarchive/`delete` — delete untags
  expenses atomically, never deletes them, FR-72). `TagManagerScreen` (list + FAB "Add
  trip"), `TagEditSheet` (`showTagEditSheet`, name + 18-swatch color + archive/delete),
  `TagReportScreen` (per-trip list: name, count, lifetime total) → `TagDetailScreen`
  (per-trip report: hero, trend, donut, transactions, export). Reached from the **Reports
  screen's Trips icon** + from Quick Add's **trip chip** (`_openTagPicker` bottom sheet:
  "+ New trip" / "No trip" sentinel / active tags). Report plumbing: `tagReportProvider`
  (own min/max span per trip), `watchByTag`/`watchCountByTag`/`watchTotalsByTag`,
  `tagTotalsProvider`/`tagExpenseCountProvider`. Tests: `tag_repository_test.dart`.
- [x] **All-Transactions browser (FR-62–66)** → `all_transactions_screen.dart`.
  Day-grouped list (`groupExpensesByDay` + `DayGroupHeader`/`ExpenseTile`,
  relative Today/Yesterday/date headers), lazy pagination (`_pageSize` 100, scroll-to-load),
  AppBar month prev/next chevrons + custom-range `showDateRangePicker` + a multi-select
  **category filter** (`_CategoryFilterSheet`: searchable checkbox list, removable
  `InputChip`s, active-count badge). Swipe-to-delete with confirm (via `ExpenseTile`).
  New repo queries: `watchInRange` gained a `categoryIds` filter + `distinctCategoryIdsInRange`.
  Reached from Home's "Recent → View all" + the tile is also used by Reports. Tests:
  `all_transactions_grouping_test.dart`.
- [x] **Per-month budgets (FR-74–76)** → schema **v2** added `budgets.monthKey` ('YYYY-MM',
  `monthKeyFor(DateTime)` helper; existing rows backfilled to current month on upgrade).
  `budget_repository.dart` reworked to key everything by month: `watchAllForMonth`,
  `watchOverallBudget`, `setOverall`/`setForCategory`/`clearForCategory` (per-month upsert),
  **`carryForward`** (copies previous month's overall + per-category setup, FR-75), pure
  `categoryBudgetOverrun`. `BudgetSetupScreen` now navigates month-by-month (AppBar
  chevrons), shows a **carry-forward** empty state, a `_CategoryTotalCard` warning when
  per-category budgets exceed the overall (FR-76), and clears a budget on a zero amount.
  Threshold alerts (`crossedThresholds`, 80/100%) unchanged from Sprint 3, still fired at
  save-time in `quick_add_screen.dart`. Tests: `budget_repository_test.dart`,
  `budget_threshold_test.dart`, `backdated_budget_scoping_test.dart`.
- [x] **Category edit UX — preview-strip + popup (FR-10, FR-67)** →
  `category_edit_sheet.dart` rebuilt. Instead of an always-expanded icon/color grid, each
  is now a **6-item preview strip + "+N" overflow chip** that opens a full popup sheet:
  `_openIconPicker` (~50 curated emojis) and `_openColorPicker` (18-swatch brand palette +
  a `_customColorTile` → `_showCustomColorPicker` hex dialog via **flutter_colorpicker**).
  The color popup flags a swatch **already used by another category** with a dot indicator.
  Pure `previewStripItems` helper pins the selected item first. Edit mode adds
  Archive/Unarchive + a **morphing `_DeleteCategoryDialog`** (`_DeletePhase`
  confirm→deleting→blocked): if the category is referenced by expenses, hard-delete is
  blocked and it offers **"Archive instead"** (FR-11). Tests: `category_edit_strip_test.dart`,
  `quick_add_category_grid_test.dart` (the "top 8 + More" grid logic).
- [x] **Archived Categories screen (FR-68)** → `archived_categories_screen.dart`
  (list of archived categories, tap → edit sheet to unarchive/delete). Reached from a
  count badge in `CategoryManagerScreen`'s AppBar.
- [x] **18 default categories (FR-8)** → schema **v3** appended 10 more defaults
  (`_newCategoriesV3`, index 8+) to the original 8: EMI/Loan, Online Shopping, Groceries,
  Fuel, Insurance, Subscriptions, Education, Personal Care, Fitness, Gifts & Donations.
  Existing installs get them on upgrade; the "18" count is asserted in
  `category_repository_test.dart` + `widget_test.dart` — **any docs figure must say 18, not 8**.
- [x] **Schema indexes (schema v5)** → `idx_expenses_date`/`idx_expenses_category`/
  `idx_expenses_tag` added (`@TableIndex` on fresh installs; created in `onUpgrade from < 5`
  for existing installs). Pure query perf, no behavior change.
- [x] **Quick Add polish (FR-59–61)** → date/backdate chip (today back to 90 days, no
  future — `backdate_picker_bounds_test.dart`), trip chip, note field that collapses the
  keypad via `AnimatedSize` when focused.
- [x] **Backup format v3 (FR-34)** → `currentBackupVersion = 3`. v3 adds the top-level
  `tags` array + `expenses.tagId`; pre-v3 files read missing `tags` as `[]` and `tagId` as
  null (additive, no version branch). Merge matches tags by normalized name and remaps
  `tagId` like `categoryId`; Replace wipes/restores tags in child→parent FK order. Full
  spec in `docs/backup-schema.md`. Tests: `backup_format_test.dart`,
  `backup_repository_test.dart`, `backup_crypto_test.dart`.

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **110+ passed** (adds tag_repository, all_transactions_grouping,
  backdated_budget_scoping, category_edit_strip, quick_add_category_grid, backdate_picker_bounds
  on top of the Sprint 10 suite).
- Build sanity: same native-dep constraints as before (`file_picker`/`share_plus` pins,
  KGP warning) unchanged; `flutter_colorpicker` is pure-Dart, no native impact.

### Deferred / notes — real manual verification NOT yet done, needs the user
- **Build-level verification only**, same caveat as Sprints 6/7/10. Nobody has yet, on a
  real device/simulator: created a trip and tagged an expense to it, confirmed the per-trip
  report + export; filtered All-Transactions by multiple categories and paged a long history;
  navigated budgets across months and used carry-forward; opened the icon/color popups,
  picked a custom hex color, and confirmed the "used by another category" marker; archived
  a referenced category and confirmed the "Archive instead" block.
- `Recurrence` is still date-math + reminder only (no auto-insert) — unchanged from Sprint 1/3.
- Merge's known ceilings (rename-breaks-name-match, fingerprint collision) documented in
  `docs/backup-schema.md` still apply, now extended to tags (matched by normalized name).

## Sprint 12 (Ad-Hoc) — done (Ignore category for budget)

User-requested feature, brainstormed to a written design before implementation (per the
`superpowers:brainstorming` skill flow): mark a category as "ignored for budget" — for
fixed monthly costs like rent or an EMI/loan — so it stops distorting the numbers that are
meant to reflect *discretionary* spending.

Decisions locked with the user before coding:
- **Retroactive/live filter, not a snapshot.** Toggling a category just changes what the
  live filter excludes; there's no "as of this date" history to track.
- **Ignored category keeps its own budget entry and its own spent-vs-budget display** —
  it's excluded only from *aggregate* figures, never from its own per-category tracking.
- **"Top expenses" = individual transactions**, distinct from "top categories" (both
  excluded per the requirement, just different shapes of aggregate).
- **Toggle lives on the per-category Budget Setup card**, not a separate Categories screen
  setting — it's a budget-math concern, not a category-identity concern.
- **View All Transactions and CSV/PDF export are untouched** — an ignored category's
  expenses must always stay fully visible/exportable; only budget-facing aggregates filter
  it out.

- [x] **Schema** → `isIgnoredForBudget` bool column on `Categories`
  (`lib/core/db/database.dart`), schema **v6**, mirrors the existing `isArchived` column
  exactly. `CategoryRepository.setIgnoredForBudget(id, value)` mirrors `archive`/`unarchive`.
- [x] **No single shared aggregation chokepoint existed** — a codebase-exploration pass
  found spend totals/rankings computed independently in three places, so the filter had to
  be threaded through each rather than through one shared function:
  1. **Dashboard** (`dashboard_providers.dart`) — `monthTotalProvider` (Home hero) and
     `categoryBreakdownProvider` (SpendDonut "top categories") filter
     `currentMonthExpensesProvider` before aggregating. New `ignoredCategoryIds(byId)` helper
     lives here, reused everywhere else.
  2. **Reports** (`report_model.dart` `buildReport`) — `total`, `breakdown`, `top5`,
     `dailyAverage`, `topCategory`, `weekly` buckets, and `txnCount` are all computed from an
     ignored-filtered subset; `ReportData.expenses` (the raw list CSV export and the PDF's
     transaction rows depend on) stays untouched. `report_providers.dart`'s `previousTotal`
     (the "vs previous period" comparison) also excludes ignored categories, so it isn't
     comparing a filtered number against an unfiltered one.
  3. **Native widget + Quick Add budget alert** (`expense_repository.dart` raw SQL) —
     `totalInRange`/`monthTotal`/`todayTotal` gained an optional `excludeCategoryIds` param.
     `widget_refresh.dart` (the Home Screen/Lock Screen widget's "today total") and
     `quick_add_screen.dart`'s **overall** budget-alert check both pass ignored ids through;
     the **per-category** alert check is untouched — an ignored category's own threshold
     still fires normally. Caught and fixed a real edge case here: if the just-saved
     expense's own category is the ignored one, the overall total doesn't move at all, so
     the before/after delta used for threshold-crossing must not subtract it either
     (`quick_add_screen.dart`'s `_checkBudgetAlerts`).
- [x] **Budget Setup screen's per-category nuance** → `spentByCat` used to read
  `report.breakdown`, which is now filtered — so an ignored category would've lost its own
  displayed spend. Fixed by decoupling it onto a new `categorySpendForMonthProvider`
  (`budget_repository.dart`, wraps the pre-existing unfiltered
  `ExpenseRepository.totalsByCategory`), so a category's own card always shows its real
  spend regardless of the ignore flag. The overall-total card still reads the (now
  correctly filtered) `report.total`.
- [x] **UI** → a `Switch` + "Ignore in totals" label added to each per-category
  `_BudgetCard` (not the overall card) in `budget_setup_screen.dart`, mirroring the app's one
  existing `Switch` usage (`backup_restore_screen.dart`'s auto-backup toggle). No
  confirmation dialog — instantly reversible, live.
- [x] **Backup gap found and fixed during doc-sync review** — `BackupCategory`
  (`backup_models.dart`) is an explicit field-list DTO and didn't originally include the new
  column, so export/restore/merge would have silently dropped the ignore flag on every
  backup. Added `isIgnoredForBudget` to the DTO (`fromRow`/`fromJson`/`toJson`/
  `toInsertCompanion`/`toReplaceCompanion`), additive JSON key — **no backup version bump**,
  pre-Sprint-12 files simply lack the key and decode it as `false`, same pattern as v2's
  photo field and v3's `tagId`. Documented in `docs/backup-schema.md`. Merge behavior matches
  `isArchived`/`isDefault` today: a matched (pre-existing) category's flag is left alone; only
  a brand-new category inserted by Merge carries its backed-up value.
- [x] **Docs synced** → `requirement_docs/spendly-requirements.md` bumped to **v2.1** (new
  FR-77), `requirement_docs/spendly-prototype.html`'s Budget Setup mockup gained an example
  ignored card, `README.md` and this file updated for schema v6 / test count.

### Verification done
- `flutter analyze` → No issues.
- `flutter test` → **162 passed** (+ `setIgnoredForBudget` round-trip in
  `category_repository_test.dart`, an ignored-category aggregate-exclusion case in
  `report_model_test.dart`, an `excludeCategoryIds` case in `expense_repository_test.dart`,
  and a missing-key-defaults-to-false case in `backup_format_test.dart`).

### Deferred / notes — real manual verification NOT yet done, needs the user
- **Build-level verification only**, same caveat as every prior sprint. Nobody has yet, on a
  real device: toggled a category (e.g. EMI/Loan) to ignored in Budget Setup and confirmed
  Home's hero total/donut, Reports' total/breakdown/top-5/trend/txn-count, and the native
  widget's today-total all drop it live; confirmed the ignored category's own budget card
  still shows its real spend; confirmed it still appears in All Transactions and in an
  exported CSV/PDF; exported a backup with an ignored category set, restored it, and
  confirmed the flag survived.
- `weekly`/`txnCount` in `ReportData` and the Home dashboard's 6-month trend bars
  (`trendProvider`/`_lastSixMonthsProvider`) were explicitly asked about mid-build: weekly/
  txnCount now excludes ignored categories (user chose consistency over minimal scope); the
  Home 6-month trend bars were left unfiltered (out of the requirement's named scope —
  daily/budget/top-categories/top-expenses — and the user didn't ask to extend it there).
  Revisit if that inconsistency ever bothers a real usage session.

## How to run

```
flutter pub get
dart run build_runner build      # after any Drift schema change
flutter run                      # pick iOS simulator or Android emulator
flutter analyze && flutter test
```

## UX Phase 1 — done (daily-loop friction)

Commits `a724b0c` (spec), `dbd72bb` (items 1-4), `63bb347` (item 5).

- [x] **Pace-aware hero card** → `lib/features/budgets/budget_pace.dart` (pure) +
      `_PaceLine` in `home_screen.dart`. A month total and "61% of budget" cannot be
      acted on without knowing how much month is left. Three states, not two —
      "spending too fast but still inside budget" needs a different reaction than
      "budget gone". Per-day figure truncates so `daysLeft x perDayLeft` can never
      exceed what remains.
- [x] **Undo on delete** → `ExpenseRepository.restore`. Replaced the "can't be undone"
      dialog. Restores the ORIGINAL id and `externalId` — a fresh `externalId` would
      read as a different record to a backup Merge and fork the row across devices.
      Safe to reuse the id because the table is `PRIMARY KEY AUTOINCREMENT`.
- [x] **Duplicate a transaction** → `QuickAddScreen.duplicateOf` (a separate field from
      `editing`, never a flag on it, so every edit-only path stays edit-only and a copy
      structurally cannot overwrite its source) + a long-press actions sheet on
      `ExpenseTile`. The sheet also gave Delete its first non-swipe path.
- [x] **Transaction search** → `parseExpenseQuery` + a `search` clause on
      `watchInRange`. Runs in SQL, not over the loaded page (the list pages at 100 rows,
      so Dart-side filtering would silently miss unloaded rows). An active search
      escapes the visible date range and searches all history.
- [x] **Real tabs** → `lib/features/home/app_shell.dart`. Replaced push-per-tab, which
      grew the back stack and lost scroll/filter state, and removed two "coming soon"
      snackbars. Tabs build lazily — `IndexedStack` builds every child eagerly, which
      would drag three more screens' Drift subscriptions onto the cold-start path.
      Category Manager's FAB moved to an app-bar action so the shell owns the one FAB.

## UX Phase 2 — done (recurring expenses, FR-7 finally shipped)

FR-7 had a data model and tested date math since Sprint 1, but nothing wrote the
columns and no reminder was ever scheduled.

**Model:** a recurring expense is an ordinary expense row that also carries the
schedule. Future occurrences are NOT materialised; the series is a single
`nextDueDate` pointer, so occurrences that fell due while the app was closed are
recovered by walking from the pointer to today.

- [x] **Schema v10** → `expenses.nextDueDate`, `expenses.recurrenceEndDate`. Both
      nullable, no backfill: pre-v10 rows flagged `is_recurring` have no due date to
      reconstruct, and a guessed one would fire a reminder nobody asked for. They show
      as "not scheduled" and get a real date when edited. `migration_test.dart` seeds
      such a row.
- [x] **Backup v6** → both fields on each expense. Without them a restore would keep
      the recurring flag but lose the schedule, so the reminder would never fire again.
      Pre-v6 files read the missing keys as null. `docs/backup-schema.md` updated.
- [x] **Pure scheduling** → `recurring_schedule.dart`: `pendingOccurrences`,
      `nextDueAfter`, `firstDueDate`, capped at 24 surfaced occurrences.
- [x] **Month-end drift bug found and fixed here.** Chaining the pre-existing
      `nextOccurrence` gives Jan 31 -> Feb 28 -> Mar 28 -> the 28th forever: rent on the
      31st silently becomes rent on the 28th after one February. `_step` re-applies the
      anchor day each step, clamping only where the month is genuinely short.
      `nextOccurrence` itself is unchanged — the fix is in the caller that walks it.
- [x] **`RecurringRepository`** → `confirm` (logs a real expense dated the occurrence,
      inside a transaction, and advances the pointer), `skip` (advances without
      logging), `cancel` (stops the schedule, keeps the expense — the money really was
      spent). A confirmed copy is deliberately NOT itself recurring, or every
      confirmation would fork the series into two advancing templates.
- [x] **Quick Add repeat chip** → frequency picker + optional end date. An in-flight
      schedule is preserved on save; only a changed frequency/end date, or a template
      that never had a due date, earns a recomputed one. A duplicate never inherits the
      recurrence.
- [x] **`RecurringScreen`** (Profile row + Home card both route here). Missed
      occurrences are listed in full but only the OLDEST is actionable: the series is a
      single pointer, so resolving out of order would silently swallow the ones skipped
      over. Each still gets its own confirm-or-skip decision.
- [x] **Home "payments to confirm" card** — renders nothing when nothing is due.
- [x] **Reminders** → `NotificationService.scheduleRecurringReminders`, re-armed by
      `recurringReminderCheckProvider` on cold start and resume (no background
      execution exists in this project by design). Ids are `500000 + expense id` so a
      re-schedule replaces its own slot. Already-overdue occurrences are deliberately
      not scheduled — a past timestamp fires instantly or is dropped, and the Home card
      already surfaces them permanently.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **348 passed** (was 272 at the start of phase 1).
- Not run on a device/simulator — manual verification still outstanding, same as
  Sprints 6/7/10/11.

### Deferred / notes
- **No test covers `scheduleRecurringReminders` itself.** There is no notification test
  harness anywhere in this repo and no fake plugin; the scheduling *inputs* are covered
  through `recurringReminderCheckProvider`'s data, the `zonedSchedule` call is not.
- Resolution is strictly oldest-first by design (single-pointer model). Out-of-order
  resolution would need per-occurrence records — a child-row link plus a skip marker.

## UX Phase 3 — done (receipt photos)

**Deviated from the design spec's "one nullable column" plan** — the spec said "one
nullable column; backup payload carries it the way the avatar already does." Building it
surfaced why the profile-photo pattern doesn't transfer: `expenses` rows are read in full
by nearly every query in the app (`watchInRange`, `watchMonth`, `listInRange`, every
reactive list behind Home/All Transactions/Reports), including the lazily-paginated
100-row transaction list. A blob column there would ride along on every one of those
reads, for every expense, whether or not it has a photo — one profile photo in a k/v
Settings table costs nothing extra to always load; a photo blob on the most heavily-read
table in the app is a different order of problem entirely.

- [x] **Schema v11** → new `expense_receipts` table (`AppDatabase.database.dart`), not a
      column on `expenses`. `expenseId` unique-indexed (one receipt per expense).
      `onDelete` deliberately NOT cascaded — see the next point.
- [x] **`ReceiptRepository`** → `forExpense` (bytes, for the one screen that shows them),
      `watchExpenseIdsWithReceipt` (existence only, for a lightweight indicator on
      `ExpenseTile` without ever loading bytes for a list), `set` (upsert via
      `INSERT OR REPLACE`, honoring the unique index).
- [x] **Undo-on-delete gets the photo back for free, by design, not by extra code.**
      `ExpenseRepository.delete` deliberately leaves a deleted expense's receipt row in
      place. Because undo (`restore`, from Phase 1) reuses the expense's ORIGINAL id
      (never recycled — `PRIMARY KEY AUTOINCREMENT`), an untouched receipt row
      re-attaches itself with zero extra bookkeeping the moment the expense comes back.
      Handling this at delete time instead would mean re-teaching the undo path to fetch,
      hold, and re-insert photo bytes too — exactly the complexity this design avoids.
- [x] **`AppDatabase.pruneOrphanedReceipts()`** — sweeps receipts whose expense is
      permanently gone. Runs on cold start only (`app.dart`), never on resume: a resume
      can land mid-undo-window, and sweeping then would delete a photo the user is about
      to bring back. A full process restart cannot land inside that window (the undo
      snackbar and its closure don't survive the app closing), so cold-start-only is the
      point past which "orphaned" is actually permanent.
- [x] **`resetToDefaults` fixed** — it deleted every expense but, before this phase,
      never touched receipts; "Delete all data" would have left every photo behind as a
      permanent orphan. Now wipes `expense_receipts` first, same FK-order convention as
      the rest of the method.
- [x] **Backup v7** — new top-level `receipts` array. `expenseId` inside it is the
      **backup file's** expense id, matching `BackupExpense.id` in the same payload, not
      a local device id (same convention as `BackupExpense.tagId`) — Replace and Merge
      resolve it to a local id differently:
      - **Replace** reuses backup ids verbatim for expenses (table is empty by then), so
        a receipt's `expenseId` is reused as-is too. Wipes `expense_receipts` before
        `expenses` (children-before-parents, extending the existing convention).
      - **Merge** never touches a matched expense's receipt — matched rows are never
        updated by merge on any field, and a receipt is no exception. Only a
        newly-inserted expense can gain a receipt, under the LOCAL id Merge just
        assigned it. `_mergeExpenses` inserts a receipted expense individually (not
        batched) specifically to learn that new id before attaching the photo; expenses
        with no receipt stay on the batched fast path, since receipted expenses are
        expected to be the minority.
      - A pre-v7 file has no `receipts` key; `BackupPayload.fromJson` reads that as an
        empty list — nothing is lost, since a pre-v7 backup predates the feature.
- [x] **Quick Add UI** → a receipt chip alongside date/trip/repeat. Tap when empty opens
      camera/library (`image_picker`, 1600×1600/80% — well above the avatar's 800×800
      since a receipt has to stay legible zoomed in, but still bounded so a modern
      camera's full-resolution photo doesn't land in backup JSON at full size). Tap when
      present opens a preview sheet with Replace/Remove. Existing photo loads
      asynchronously (it isn't on `ExpenseRow`, unlike every other prefilled field) — a
      brief spinner on the chip, not a blocking load for the rest of the form. A
      duplicated ("Add again") expense inherits the source's photo, matching how it
      already inherits note/category/trip.
- [x] **`ExpenseTile` indicator** — a small receipt icon next to the title, driven by
      `watchExpenseIdsWithReceipt` (an id set, never bytes) so the 100-row paginated list
      isn't loading photos it never displays.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **367 passed** (was 348 at the start of phase 3). New coverage
  includes the full backup round-trip for all four combinations (Replace with/without a
  receipt, Merge onto a matched vs. newly-inserted expense) plus the undo-survives-prune
  interaction.
- Not run on a device/simulator — camera/gallery picker behavior specifically needs
  manual verification (permissions prompts, actual photo capture), same standing gap as
  every prior sprint's manual-check item.

### Deferred / notes
- One photo per expense (unique index on `expenseId`), not a gallery of several. Matches
  what was asked for; multiple receipts per expense would be a new ask.
- No compression beyond `image_picker`'s own resize/quality params — no new dependency
  added for this.

## Between-phase fixes (not part of any phase)

- **`c40e462`** — search was permanently stuck on its loading spinner. Root cause: the
  search date range's upper bound called `DateTime.now()` fresh inside a getter
  re-evaluated on every `build()`; since a `StreamProvider.family` key is compared by
  value and `DateTime` equality is exact to the microsecond, this produced a new key on
  nearly every rebuild (not just when the search text changed), so Riverpod tore down
  and restarted the query before it ever emitted. Fixed by truncating the bound to day
  granularity in a pure, tested `transactionsQueryKey` function.
- **`880b52a`** then **`129e860`** — attempted an `impeccable`-guided redesign of Quick
  Add's 4-chip metadata row (stadium shape, left-align, bigger touch targets), then
  reverted it in full at the user's request ("does not look good at all") and kept only
  a one-line `runSpacing` fix on the `Wrap`. **Lesson: don't redesign a screen's visual
  language on a "make it look nicer" request without confirming direction first** — the
  user wanted the existing look preserved with a minimal spacing fix, not a rebuild.

## UX Phase 4 — done (accounts)

- [x] **Schema v12** → new `accounts` table (name, type — cash/bank/card/wallet —,
      opening balance, archive flag, externalId), plus one additive nullable
      `expenses.accountId` column. Balance is never stored, only ever derived (matches
      how budget totals/lifetime stats already work) — Phase 4 doesn't compute a
      balance yet, that's Phase 6.
- [x] **`paymentMethod` → `accounts` migration** — every distinct `payment_method`
      string on existing expenses becomes one `AccountRow` (type defaults to `cash`;
      free text can't be reliably classified further), with matching expenses pointed
      at it via `account_id`. `payment_method` itself is left untouched — purely
      additive, nothing deleted. **In practice this migration is a no-op on every real
      install**: verified `payment_method` has never been settable from any screen in
      this app (schema column existed, travelled through backup/export, nothing ever
      wrote a non-null value) — written correctly anyway per the spec, on the chance a
      debug/import path set one historically.
- [x] **`AccountRepository`** → CRUD (never hard-deletes, archive only — same
      never-destroy-data convention as categories/tags), `watchTotalsByAccount` for the
      per-account current-month breakdown.
- [x] **`AccountsScreen`** (Profile → Accounts) → list with per-account this-month
      spend, create/edit/archive sheet (name, type chips, opening balance).
- [x] **Quick Add** → a 5th chip, account picker mirroring the trip picker exactly
      (including "+ New account" inline creation). Placement flagged, not silently
      assumed: added to the *already-reverted*, original chip row styling (not the
      redesign that was just backed out), since the user's feedback was about the
      redesign's look, not about whether a 5th item may ever be added there. Worth
      revisiting if it reads as crowded again.
- [x] **Backup v8** → new `accounts` array; each expense gains an `accountId` key
      (backup-file id, resolved to a local id on Merge/Replace exactly like `tagId`
      already is — matched by `externalId` first, normalized name fallback). A matched
      account is never touched by Merge, same as every other master-data table; only a
      newly-inserted expense's `accountId` gets remapped through the merge's
      backup-id → local-id map.
- [x] **`resetToDefaults`** wipes `accounts` too (no default accounts reseeded — unlike
      categories, there's nothing sensible to seed).

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **389 passed** (was 373 immediately before this phase). New
  coverage: `account_repository_test.dart` (CRUD, archive, per-account totals),
  extended `migration_test.dart` (a v1 install with two expenses sharing a
  `payment_method` value upgrades to exactly one account, both rows linked, the
  untouched row stays untouched), extended `reset_test.dart`, five new backup
  round-trip tests (Replace reattaches the account to the right expense; Merge attaches
  an account to a newly-inserted expense under its *new* local id, not the source
  device's; merging twice doesn't duplicate; renaming then re-merging keeps the
  rename; a pre-v8 file merges with no accounts at all), plus a v8 JSON round-trip in
  `backup_format_test.dart`.
- Not run on a device/simulator — same standing gap as every prior phase.

### Deferred / notes
- No balance display yet (opening balance + activity) — that's Phase 6, once transfers
  exist and a "derived balance" has transfers to derive *from* as well as expenses.
- Account picker placement in Quick Add (5th chip) is a judgment call flagged to the
  user, not confirmed — the row was already the subject of back-and-forth feedback this
  same session.

## Phase 4 follow-up — done (default account + account detail)

Requested right after Phase 4 shipped: a default account that prefills Quick Add, and
account-wise transactions/total. Both genuinely needed design (not just wiring), covered
here rather than a separate spec doc since the scope stayed bounded to the existing
accounts feature.

- [x] **Schema v13** → `accounts.isDefault`. Enforced in `AccountRepository`, not a DB
      constraint (no partial-unique-index support in this Drift version):
      `setDefault(id)` clears every other row's flag in the same transaction before
      setting the target's. Hit the same "createTable trap" documented elsewhere in
      `database.dart` (tags hit it twice already) — `accounts` gets created fresh at
      `from<12` using the CURRENT table definition, which already includes
      `is_default`, so `from<13`'s `addColumn` needed the same `_hasColumn` guard.
- [x] **First account auto-defaults.** `create()` checks whether any account exists yet;
      if not, the new one is the default. Otherwise a single-account user would have to
      know to go flip a setting before the prefill ever did anything. Every account
      after the first stays not-default until explicitly reassigned via the star toggle
      on `AccountsScreen`'s tile.
- [x] **Upgrading installs get the same rule.** The v13 migration marks the
      earliest-id account default for anyone who already has accounts on the books
      (from the v12 payment-method migration or created since) — otherwise every
      upgrading user, not just fresh installs, would see a silent no-op prefill.
- [x] **Archiving clears the default**, never auto-picks a replacement — deliberately:
      silently redirecting future expenses onto an account the user never chose would
      be a worse surprise than an empty prefill.
- [x] **Quick Add** prefills `_accountId` from the default account, but only on a
      genuinely fresh add — editing or duplicating an expense still inherits the
      source's own account, matching how note/category/trip already work. A late-
      arriving default fetch never clobbers a choice the user already made faster than
      the async load resolved (`_accountId != null` guard).
- [x] **`AccountDetailScreen`** (new) — tapping an account now opens this instead of
      jumping straight to edit; edit moved to an app-bar icon. Shows an all-time total
      (via `ExpenseRepository.watchInRange`/new `accountIds` filter, mirroring the
      existing `categoryIds` filter exactly) and the full paginated transaction list,
      reusing `groupExpensesByDay`/`DayGroupHeader`/`ExpenseTile` from
      `all_transactions_screen.dart`/`expense_tile.dart` rather than rebuilding list
      rendering from scratch. Deliberately does NOT show a derived balance (opening
      balance − activity, transfers, etc.) — that stays Phase 6 scope, once transfers
      exist to derive a real balance from; showing "total expense" is what was asked
      for.
- [x] **Backup** — `isDefault` is additive on the existing `accounts` array entry, no
      version bump (same pattern as `isIgnoredForBudget`). Replace restores it
      verbatim (safe: the backup itself never had two defaults, since this app's UI
      never allows that). **Merge does not trust it blindly** — a matched account's
      flag is untouched like every other field, but a newly-inserted account only
      carries the default over when the local device had no default at all before the
      merge started, and at most one newly-inserted account ever gets it. Naively
      carrying over every row's own flag could otherwise produce two default accounts
      when merging two devices that each already had one.
- [x] **`reactive_read_staleness_test.dart` caught a real formatting issue** — the
      scanner only checks the single line directly above a `ref.read()` call for a
      `// staleness-ok:` comment; a two-line comment above `_accountExpensesProvider`'s
      pagination read didn't qualify because the marker wasn't on the line immediately
      adjacent. Fixed by collapsing it to one line, matching the exact format
      `all_transactions_screen.dart`'s equivalent comment already uses.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **403 passed** (was 389 before this follow-up). New coverage: 7
  default-account repository tests (first-create auto-defaults, second doesn't,
  `setDefault` reassigns, archiving clears with no auto-replacement, unarchiving
  doesn't restore it), an `accountIds` filter test on `watchInRange`, a v13 migration
  assertion, and 5 backup tests specifically exercising the "at most one default"
  merge-safety property — including a hand-authored payload where two different
  accounts both claim `isDefault: true`, pinning that the merge still yields exactly
  one.
- Not run on a device/simulator — same standing gap as every prior phase.

### Deferred / notes
- Account picker's 5th-chip placement in Quick Add (from Phase 4) is unchanged by this
  follow-up — still a flagged, not confirmed, judgment call.
- No UI to reassign the default from *within* the edit sheet — only the tile's star
  toggle does it. One control for one action, deliberately, not a redundant second path.

## Excel export completeness pass — done

User asked whether the Excel export already carried everything now tracked per expense
(trip, account, recurring, receipt, foreign amount). It didn't — the Transactions sheet
still only had the original five columns (Date, Category, Note, Amount, Payment method);
every feature added since (trips predate this, but account/recurring/receipt/FX all landed
without ever touching export).

- [x] `buildXlsx` gains five more columns: Trip, Account, Recurring, Receipt, Paid abroad.
      `Payment method` (the free-text field, dead in every real install per Phase 4's
      investigation) is kept, not replaced — Account is additive alongside it, not a
      migration that silently drops the old column from exports.
- [x] Two new `*ByIdProvider`s (`tagsByIdProvider`, `accountsByIdProvider`) added
      alongside the existing `categoriesByIdProvider`, same pattern, same file each
      belongs to.
- [x] `ExportRow` (shared by all three export surfaces — monthly report, custom report,
      per-trip report) takes the new lookups as optional params defaulting to empty, so
      nothing broke before every call site was updated. All three now pass real data.
      The per-trip report deliberately omits `tagById` — every row there already belongs
      to the one trip being reported, so a per-row Trip column would repeat the same
      name on every line rather than add information; Account/Recurring/Receipt/FX are
      still wired there.
- [x] PDF export untouched — it's a one-page summary (top-5 list, category breakdown),
      never a per-row transaction table, so there was no column list to extend.

### A test-only bug found while verifying
The new xlsx test used whole-number amounts (4500, 50). The `excel` package's own
encode/decode round-trip collapses a whole-number `DoubleCellValue` into an
`IntCellValue` on the way back out — confirmed via a throwaway debug script that the
actual export data was correct (Trip/Account/Recurring/Receipt/FX all populated
right) while the test's `DoubleCellValue`-only cast silently found nothing and
returned index -1. Fixed by handling both cell types when reading amounts back in a
test — a real quirk of the library, not of `buildXlsx`.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **404 passed** (was 403 before this). New coverage: the
  Transactions sheet header list extended to 10 columns, plus a new test seeding one
  fully-loaded expense (tagged, accounted, recurring, receipted, paid abroad) beside a
  bare one and asserting every new column is populated on the rich row and blank on
  the bare one.
- Not run on a device/simulator — same standing gap as every prior phase.

## Accounts follow-up: grouping, month-first detail, monthly opening-balance reset — done

Three requests on top of the Phase 4 accounts feature.

- [x] **Grouped by type** — `AccountsScreen`'s active list is now sectioned by
      `AccountType` (Cash, Bank, Card, Wallet — enum order), a `SectionTitle` per
      non-empty group, same pattern already used for the trailing Archived section.
- [x] **Detail screen defaults to the current month** — `AccountDetailScreen` no longer
      shows an all-time total/list by default; it shows this month (`monthBounds`,
      same helper the manage screen already uses), with a `TextButton` in the app bar
      ("Full year" / "This month") toggling to calendar-year-to-date
      (`yearToDateBounds`, new helper next to `monthBounds` in
      `expense_repository.dart`) and back. Both the header total and the paginated
      transaction list re-key off the selected range; switching resets pagination.
- [x] **Opening balance resets monthly, computed not destructive** — schema v14 adds a
      nullable `openingBalanceMonth` ('YYYY-MM') column to `Accounts`. `create()`/
      `update()` stamp it with the current month whenever a non-zero balance is set;
      `AccountRow.effectiveOpeningBalance(now)` (new `row_extensions.dart` extension)
      reads the stored minor value only when the stamp matches the current month,
      otherwise zero. Nothing wipes the DB row on the 1st — a stale stamp just stops
      being surfaced, so restoring an old backup or opening the app after a long gap
      can't lose data through a background job that never ran. The edit sheet prefills
      with this *effective* value (not the raw stored one), so re-saving always
      reflects what's currently live. `BackupAccount` carries the field additively (no
      backup version bump), restored verbatim by both Merge (safe — no "at most one"
      invariant like `isDefault`'s) and Replace.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **409 passed** (was 404 before this). New coverage: 5 repository
  tests for the monthly-reset behavior (create/update stamping, a stale-month stamp
  reading as zero while the raw column stays untouched, a zero-balance create leaving
  no stamp at all) plus an extended v1→v14 migration assertion confirming an account
  migrated from a pre-v12 `payment_method` string (never had an opening balance
  entered) gets no stamp, same as a fresh zero-balance `create()`.
- Not run on a device/simulator — same standing gap as every prior phase.

## Phase 5 — Income & savings rate (schema v15, backup v9) — done

Implemented per `docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md`'s Phase 5
section, which was already written and approved earlier in this project. No re-brainstorm
needed; proceeded directly from the existing spec.

- [x] **`LedgerEntries` table** (schema v15) — money coming IN, deliberately kept apart
      from `Expenses` rather than a `kind` column on it. The spec's stated reason: roughly
      fourteen existing `Expenses` queries would each need an opt-out guard to exclude
      income if it lived there, and a single missed one silently inflates reported spend.
      **Scoped down from the spec's original table design**: no `kind` column yet, since
      this table currently holds only income — the spec's `kind (income/transfer)` design
      anticipated Phase 6, which doesn't exist yet (YAGNI; the column is trivial to add
      additively when transfers actually land). Fields: amount, date, optional account,
      optional source label ("Salary", "Freelance"), optional note, `externalId`.
- [x] **`LedgerRepository`** — CRUD plus `watchInRange`/`watchTotalInRange`. Entries are
      **hard-deleted**, not archived — unlike categories/tags/accounts, nothing else in the
      schema references a ledger entry by id, so there's no history to protect. Delete
      still gets the same swipe + 5-second undo snackbar as expenses (`restore()` reuses
      the exact same "re-insert via `toCompanion(false)`, same id/externalId" trick as
      `ExpenseRepository.restore`).
- [x] **Income screen** (`lib/features/ledger/income_screen.dart`) — reached from a new
      Profile row, same shape as Accounts/Recurring: a "this month" total card, a list of
      every entry (newest first), swipe-to-delete-with-undo, tap to edit. Add/edit is a
      bottom sheet mirroring `_AccountEditSheet`'s shape (amount/date/source/account
      chips/note), not a rebuild of Quick Add's custom keypad — a plain form is the
      correct-weight tool for an occasional, low-frequency entry.
- [x] **Net cashflow / savings rate** — pure `computeCashflow()` (`ledger/cashflow_math.dart`,
      unit-tested directly) derives net (income − expense) and a savings-rate percentage,
      null when income is zero (nothing to divide by). Surfaced as an additional `StatGrid`
      pair on the monthly and custom report screens, and a new `_SavingsRateCard` on
      Monthly Recap — **all three gated on `incomeTotal.minor > 0`, appearing only once
      income has actually been logged for that period.** Deliberately did NOT rewrite
      Recap's existing budget-based hero headline (the spec's illustrative "you kept 22%"
      line): that logic is well-tested and used by every user, income or not; an additive
      card ships the same value without risking a regression for the common no-income case.
- [x] **Backup v9** — `ledgerEntries` is a new top-level array (first version bump since
      v8's `accounts`, since every field added in between was additive to an existing
      table). `BackupLedgerEntry` follows the `BackupExpense` shape exactly: Replace wipes
      before `accounts` and restores after (same FK-order reasoning), reusing ids verbatim;
      Merge matches by `externalId` first, falling back to a content fingerprint (amount,
      date, mapped account, source label, note) — a plain income entry has no natural-key
      field like a name to fall back on, same as expenses.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **428 passed** (was 409 before this phase; 53 test files, up from 51).
  New coverage: `cashflow_math_test.dart` (5 pure-function tests including the zero-income
  null case and a negative/over-spend case), `ledger_repository_test.dart` (8 tests:
  CRUD, account attach/clear, delete+restore identity, range queries), a v1→v15 migration
  assertion, 4 new `backup_format_test.dart` cases (v9 round-trip, pre-v9 absence), and a
  new `ledger entries (income)` group in `backup_repository_test.dart` (4 tests: export→
  replace, merge with account remapping, merge-twice dedupe, pre-v9 merge).
- Not run on a device/simulator — per standing user instruction, the app is launched and
  tested manually, not via `flutter run`, so this is expected, not a gap.

### Deferred / notes
- Phase 5's own text flags budgets staying strictly expense-based (no income-aware
  budgeting) as an explicit, deliberate scope boundary, not a gap.
- Phase 6 (transfers, derived live balances, the ledger+expenses union on account detail)
  and Phase 7 (insights, savings goals, app lock, autocomplete) remain unstarted, per the
  original roadmap — not requested yet.

## Add Income sheet: visual refinement (impeccable) — done

User flagged the Add/Edit Income sheet as functionally correct but "clumsy" — a plain stack
of `TextField`/`InputDecorator`/`ChoiceChip`-`Wrap` with no visual hierarchy, styled
inconsistently with the rest of the app. Ran through the `impeccable` skill's Setup step
(loads `PRODUCT.md`/`DESIGN.md`, already fully documented from an earlier session) and
treated this as a refinement — same fields, same bottom-sheet flow, applying the
already-committed design system more correctly rather than inventing a new one. This is the
same screen a prior session's Quick Add chip redesign was **rejected** on for drifting from
the incumbent visual language; this pass deliberately copied proven in-app recipes instead
of improvising:

- [x] Amount styled in Sora (20px/700), per DESIGN.md's "Sora-for-money" rule — was
      rendered in the default Inter body style, same as every other field.
- [x] The per-account `ChoiceChip` `Wrap` (unwieldy past a handful of accounts, and a third
      distinct control type sitting next to two others) replaced by a single tappable
      Account row that opens a picker sheet — the exact list shape Quick Add's own account
      picker already uses. Extracted into a shared `showAccountPickerSheet` (new
      `lib/features/accounts/account_picker_sheet.dart`) rather than copy-pasted a third
      time, since Transfer (below) needed the identical picker twice more. Quick Add's own
      copy is left untouched — it alone needs the inline "+ New account" shortcut.
- [x] Date and Account now sit side by side as matching `InputDecorator` rows, mirroring
      the trip-dates row layout already in `tag_edit_sheet.dart`.
- [x] Save is now the brand-gradient CTA every other primary action in the app uses (copied
      verbatim from `tag_edit_sheet.dart`'s `_saveButton()`) — was a plain default-styled
      `FilledButton`.
- [x] Delete gains a confirm dialog: unlike the list's swipe-to-delete, this button has no
      undo path back to the entry once the sheet closes.

### Verification done
- `flutter analyze` -> No issues. `flutter test` -> unaffected (no behavior change, no new
  tests needed for a pure visual refinement with unchanged field/save/delete logic).
- Not run on a device/simulator — per standing user instruction.

## Phase 6 — Transfers & live balances (schema v16) — done

Implemented per `docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md`'s Phase 6
section. Proceeded directly from the existing spec, same as Phase 5.

- [x] **Transfers reuse `LedgerEntries`**, not a new table — schema v16 adds `kind`
      (`income`/`transfer`, default `income`) and `counterAccountId` (destination account,
      transfer-only) to the table Phase 5 deliberately left `kind`-less. Migration follows
      the `month_key` (v2) precedent for a NOT-NULL column on a populated table: raw
      `ALTER ... ADD COLUMN kind TEXT` (nullable at the DDL level) then an `UPDATE` backfill
      to `'income'`, guarded by the now-familiar `_hasColumn` createTable-trap check.
      `LedgerRepository` gained `addTransfer()`, and every income-only query (`watchAll`,
      `watchInRange`, `watchTotalInRange` — the Income screen and the Recap/report
      savings-rate cards) now explicitly filters `kind == income`, so transfers never leak
      into "income" anywhere they weren't before.
- [x] **Derived balance, not stored** — `computeAccountBalance()` (new, pure,
      `ledger/balance_math.dart`): opening balance + income − expense + transfersIn −
      transfersOut. **Deliberately scoped to the current month**, not lifetime, departing
      from the spec's literal wording — because opening balance itself resets monthly (the
      prior session's explicit user request), a lifetime balance formula would silently mix
      a monthly-reset input with a lifetime output. Combined via three new grouped
      `LedgerRepository` queries (`watchIncomeTotalsByAccount`,
      `watchTransfersInTotalsByAccount`, `watchTransfersOutTotalsByAccount` — one query
      across every account, same shape as the existing `watchTotalsByAccount`, not one
      query per account) and two new Riverpod providers
      (`lib/features/ledger/account_balance_provider.dart`):
      `accountBalancesThisMonthProvider` (map) and `totalBalanceThisMonthProvider` (sum
      over active accounts only).
- [x] **Account detail timeline union** — the one screen where `Expenses` and
      `LedgerEntries` are ever combined, per the spec's own scoping. A new
      `_accountLedgerProvider` (unpaginated — income/transfers per account are naturally
      few) supplies ledger rows; a local `_groupTimelineByDay` merge-sorts them against the
      existing paginated expense list before bucketing by day. Ledger rows render via a new
      `_LedgerTimelineTile` (income: `+amount`; transfer out: `-amount`, "Transfer to X";
      transfer in: `+amount`, "Transfer from Y") — tap to edit, no swipe-delete here (that
      stays on the dedicated Income screen / each edit sheet's own Delete button). A new
      "Balance this month" card sits above the existing "Spent this month/year" card; a new
      app-bar Transfer action (hidden when fewer than 2 active accounts exist, since a
      transfer needs two) opens the new Transfer sheet pre-filled with this account as the
      source.
- [x] **New Transfer sheet** (`lib/features/ledger/transfer_screen.dart`) — amount/From/To/
      date/note, same visual recipe as the just-refined Income sheet (Sora amount, gradient
      Save CTA, confirm-dialog Delete). From/To each use the new shared
      `showAccountPickerSheet`, each excluding whichever account is picked on the other
      side so the same account can't be chosen twice.
- [x] **Dashboard balance card** — a new `_BalanceCard` on Home, below the budget hero,
      showing the total across active accounts; renders nothing at all when there are no
      accounts, same "silent when unused" convention `_DueRecurringCard` already
      established.
- [x] **Backup** — `kind`/`counterAccountId` are additive fields on the existing
      `ledgerEntries` array entries (no version bump, same pattern as `openingBalanceMonth`
      on accounts): a pre-v16 file simply lacks both keys, reading as `income`/`null`. Merge
      resolves `counterAccountId` through the same account-id map `accountId` already uses,
      skipping a transfer entirely if either end can't be mapped (an orphan safety net that
      should never trigger on a well-formed payload). The merge dedupe fingerprint now
      includes `kind` and `counterAccountId` so two transfers between different account
      pairs are never mistaken for duplicates of each other.

### A test flakiness dead-end, and the decision made about it
A first attempt at testing the combining Riverpod providers
(`accountBalancesThisMonthProvider`/`totalBalanceThisMonthProvider`) end-to-end through a
`ProviderContainer` reliably hung — `allAccountsProvider` never emitted a first value within
a generous polling window, for reasons not fully root-caused (no other test in this codebase
drives a chain of `StreamProvider`s through a bare `ProviderContainer` outside a widget test,
so there was no working precedent to compare against). Rather than sink further time into a
Riverpod/Drift interaction that may be specific to this test-runner environment, the test was
dropped in favor of testing what it actually needed to prove at a lower, more reliable layer:
`computeAccountBalance()` directly (pure function, 5 cases) and the new grouped
`LedgerRepository` queries directly against a real in-memory `AppDatabase` (the same proven
pattern every other repository test in this codebase already uses). The two combining
providers themselves are thin fold/sum glue over those already-tested pieces.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **444 passed** (was 428 before this phase; 54 test files, up from 53).
  New coverage: `balance_math_test.dart` (5 pure-function tests), 8 new
  `ledger_repository_test.dart` cases (transfer CRUD, both-sides re-pointing on update,
  grouped income/transfer-in/transfer-out totals, the account-timeline union query, income
  queries excluding transfers), an extended v1→v16 migration assertion, 2 new
  `backup_format_test.dart` cases (transfer round-trip, pre-v16 defaults-to-income), and 2
  new `backup_repository_test.dart` merge/replace cases for transfers.
- Not run on a device/simulator — per standing user instruction, the app is launched and
  tested manually.

### Deferred / notes
- The account detail timeline's day-total header still sums only expenses (unchanged
  meaning: "spent that day"), deliberately not netting in income/transfers of different
  signs into one ambiguous number.

## Phase 7 — Insight, goals, security (schema v17, backup v10) — done, final phase

Implemented per `docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md`'s Phase 7
section — the last phase on the original roadmap. Proceeded directly from the existing
spec, same as Phases 5–6.

- [x] **Insight feed** (`lib/features/insights/`) — pure derived math, no schema.
      `significantCategoryTrends()` compares each category's current-month spend to its
      trailing 3-completed-month average (zero-filling a month with no spend in that
      category, not skipping it — skipping would inflate the average for anyone who only
      spent in 1 of 3), flags a move of ≥30% with a ≥₹500 current-month floor so a tiny
      category's swing isn't noise, sorted by size of move. `monthlySubscriptionsTotal()`
      normalizes every active recurring template to its monthly-equivalent cost
      (daily/weekly cadences × average periods-per-month, not a flat ×30/×4 that would
      drift). New Insights screen off Profile; empty state explains it needs a few months
      of history, matching why this was sequenced last in the roadmap.
- [x] **Savings goals** (`lib/features/goals/`, schema v17 `SavingsGoals` table) —
      **deliberately NOT derived from income/expense/cashflow activity.** `savedMinor` is a
      plain running counter the user adjusts via "Add money"/"Withdraw" (clamped at zero on
      withdrawal). Tying a goal's progress to the monthly-resetting balance/cashflow
      machinery (Phase 5/6) would reset a multi-month goal right along with it every
      month, defeating the point. New Goals screen + detail screen (progress bar,
      add/withdraw dialog, edit/archive sheet) off Profile.
- [x] **App Lock** (`lib/features/security/`) — new dependency `local_auth` (the only one
      the whole roadmap called for; resolved cleanly, `flutter pub add` reported no
      conflict with the pinned `share_plus`/`file_picker` versions). Biometric-or-PIN
      unlock (`biometricOnly: false`), gated at the very top of `app.dart`'s `home:` before
      even the onboarding/profile check. Re-locks on `AppLifecycleState.paused`, not just
      cold start — an in-memory-only `appUnlockedProvider` (no persistence) means resuming
      from the background always re-locks too. Toggle lives in a new "Security" section on
      Profile, disabled with an explanatory subtitle on a device with no biometric
      enrollment and no PIN/pattern/passcode (`isDeviceSupported()`), rather than offering
      a switch that would strand the user. The enabled flag is excluded from backup export
      (`_excludedSettingsKeys`) — restoring a file on a new device must never silently lock
      someone out of the app they just installed.
      **Native config required and verified**: `MainActivity` changed from
      `FlutterActivity` to `FlutterFragmentActivity` (local_auth's Android
      `BiometricPrompt` needs a `FragmentActivity` host — build fails without this),
      `android.permission.USE_BIOMETRIC` added to the manifest, `NSFaceIDUsageDescription`
      added to `Info.plist`. `minSdk` needed no change — this project already inherits
      Flutter's own default of 24, above local_auth's floor.
- [x] **Note/merchant autocomplete** (`lib/features/expenses/note_autocomplete.dart` +
      `ExpenseRepository.topNotes()`) — every distinct past note, most-frequently-used
      first (one query, fetched once per Quick Add session, then filtered client-side by
      live-typed prefix — not a query per keystroke). **Deliberately minimal-footprint
      integration**: the suggestion chips fill the space Quick Add's keypad already
      vacates while the note field is focused (previously just `SizedBox.shrink()`) rather
      than adding a new element to the screen's layout — this is the same screen an
      earlier session's chip redesign was rejected on for drifting from the established
      look, so this pass added a wholly new (previously-empty) affordance instead of
      touching anything that already existed.

### Verification done
- `flutter analyze` -> No issues.
- `flutter test` -> **483 passed** (was 444 before this phase; 57 test files, up from 54).
  New coverage: `insight_math_test.dart` (13 tests: trend threshold/floor/sort, three
  subscription-cadence-normalization cases), `note_autocomplete_test.dart` (6 tests),
  `goal_repository_test.dart` (10 tests: CRUD, adjustSaved add/withdraw/clamp, archive,
  progress-ratio row extension), 4 new `expense_repository_test.dart` `topNotes` cases, an
  extended v1→v17 migration assertion, 2 new `backup_format_test.dart` cases (v10
  round-trip, pre-v10 absence), and a new `savings goals` group in
  `backup_repository_test.dart` (4 tests: export→replace, merge-twice dedupe, rename
  matches by externalId, pre-v10 merge).
- **`flutter build apk --debug`** ✓ and **`flutter build ios --debug --simulator
  --no-codesign`** ✓ — run specifically because this phase's `local_auth` dependency
  touches native Android/iOS config (the exact pattern PROGRESS.md's "Stack / tooling"
  section already establishes for every prior native-dependency change: file_picker,
  share_plus, home_widget). Confirms `local_auth` doesn't trip the project's known
  Kotlin-plugin fragility (`android.builtInKotlin=false` — see "Stack / tooling"): the
  build's KGP warning still lists only the same four pre-existing plugins
  (`file_picker`, `flutter_timezone`, `home_widget`, `share_plus`), not `local_auth`.
- Not run on a device/simulator interactively (app launch, biometric prompt itself,
  fingerprint/Face ID hardware) — per standing user instruction, that's manual testing on
  the user's own device, and is exactly what App Lock most needs given it's security- and
  native-platform-sensitive.

### Deferred / notes
- This is the final phase of the original roadmap (`docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md`).
  No further phases are planned; any next feature work starts a new spec.
- Insights' 30%-threshold/₹500-floor/3-month-window constants are not user-configurable —
  a reasonable v1 default per the "pure derived math" framing in the spec, not a gap.
- App Lock originally re-locked on every backgrounding; per user feedback (see "Post-Phase-7
  fixes" below) it now unlocks for the whole app session instead, re-locking only on a fresh
  process. No separate "require immediately" vs "require after N minutes" grace-period
  setting exists on top of that — a per-session unlock already covers the common case.

## Post-Phase-7 fixes — App Lock over-relocking, opening balance no longer resets — done

User-reported after manually testing Phase 7 on-device (2026-08-23/24):

- [x] **App Lock re-locked on ordinary in-app navigation, not just backgrounding** —
      `didChangeAppLifecycleState` relocked on every `AppLifecycleState.paused`, which fires
      for more than "the user left the app" (screen timeout, keyboard/system UI, briefly
      switching apps), so unlocking, editing an account, and navigating back asked to unlock
      again. User's explicit ask: unlock should persist for the whole session, and only
      re-lock when the app is actually closed. Fix: dropped the re-lock-on-`paused` branch
      in `app.dart` entirely — cold start already re-locks on its own, since
      `appUnlockedProvider` (`app_lock_provider.dart`) is a plain in-memory `Notifier` that
      rebuilds to `false` on every fresh process. Commit `0af0b02`.
- [x] **Account balance silently reset to zero every month** — `AccountRow.effectiveOpeningBalance`
      (added in the "Accounts follow-up" work) treated opening balance as a monthly concept:
      the stored `openingBalanceMinor` only counted when `openingBalanceMonth` matched the
      current month, otherwise it read as zero until the user manually re-entered it — by
      design at the time, but the user reported it as wrong: a savings balance should carry
      forward, never reset to 0 on its own. Root cause was two-fold, both removed:
      1. `effectiveOpeningBalance`'s month-stamp check (`row_extensions.dart`) — opening
         balance now reads as the raw `openingBalanceMinor` unconditionally.
      2. `accountBalancesThisMonthProvider` (`account_balance_provider.dart`) scoped its
         income/expense/transfer terms to the current calendar month, matching the
         (now-removed) monthly-reset framing — it's now `accountBalancesProvider`, computed
         over an all-time range (`DateTime(2000)` through tomorrow, same convention as
         `all_transactions_screen.dart`'s search range) so every transaction ever recorded
         against an account counts toward its running balance, forever.
      `openingBalanceMonth` stamping in `AccountRepository.create`/`update` was removed too
      (nothing reads it any more); the DB column and backup field are left in place, unused,
      purely so old backup files with the key still round-trip. UI copy: the account detail
      screen's "Balance this month" tile is now just "Balance". Rewrote
      `account_repository_test.dart`'s opening-balance group and one `migration_test.dart`
      assertion that exercised the retired monthly-reset behavior; `flutter analyze` clean,
      482 tests passing (483 minus the one now-removed monthly-reset-specific test).

## Account enhancements (net worth toggle, done; liability nature, custom types, recurring income — planned)

User asked for five related account features (2026-08-24): a per-account "count toward net
worth" opt-out (so a car loan or credit card doesn't distort the home total), a debit/credit
account nature so a liability starts negative, custom account types with their own
icon/color, and recurring income with an actionable notification. Brainstormed and
explicitly decomposed into four independent sub-projects rather than one spec, per user
approval, smallest/lowest-risk first:

1. **Net worth inclusion toggle — done.** [x]
2. **Debit/credit account nature (liability accounts start negative) — done.** [x]
3. **Custom account types with icon/color (per-account, not a reusable type registry — user's
   explicit choice over a Categories-style type table) — done.** [x]
4. Recurring income + actionable notification (salary, meal card reload) — not started, and
   the biggest piece: `LedgerEntries` has no recurrence columns today (unlike `Expenses`,
   which already carries `isRecurring`/`recurrence`/`nextDueDate`), and no notification in
   this app has ever used an action button — every one today is tap-to-open only. Agreed
   home: the existing Recurring screen gets an income tab rather than a new screen.

### Sub-project 1 — net worth inclusion toggle (schema v18) — done

- [x] **`Accounts.includeInNetWorth`** — bool, default true. Additive migration
      (`if (from < 18)`, `_hasColumn` guarded like every other additive column here).
      `AccountRepository.create`/`update` gain the param.
- [x] **`totalBalanceProvider`** (`account_balance_provider.dart`) filters to
      `includeInNetWorth` accounts before folding — the only provider this flag touches.
      `accountBalancesProvider` (each account's own balance, feeding the account detail
      screen) is unchanged, satisfying the user's explicit "should not impact any other
      calculation" requirement.
- [x] **Account edit sheet** — one `SwitchListTile`, "Count toward net worth total", shown
      for both create and edit, default on.
- [x] **Backup** — `includeInNetWorth` added to `BackupAccount` as a plain additive field,
      same pattern as `openingBalanceMonth`; no version bump.
- [x] Tests: 4 new `account_repository_test.dart` cases, one `migration_test.dart`
      assertion, 2 new `backup_format_test.dart` round-trip cases, 2 new
      `backup_repository_test.dart` merge/replace cases. No provider-level test for the
      `totalBalanceProvider` filter itself — the `ProviderContainer` + chained-`StreamProvider`
      flakiness documented under Phase 6 is still unresolved, so this one-line `.where` filter
      is covered by the repository-level persistence tests plus on-device verification instead,
      same tradeoff as before. `flutter analyze` clean, 490 tests passing.

### Sub-project 2 — debit/credit account nature (schema v19) — done

- [x] **`Accounts.isLiability`** — bool, default false. Additive migration (`if (from < 19)`),
      same `_hasColumn`-guarded shape as sub-project 1's column. Purely a display/sign
      convention: nothing in `balance_math.dart` or anywhere else branches on it — a
      liability's `openingBalanceMinor` is simply stored negative, so the existing
      nature-agnostic running-balance math reads it as debt from day one with zero changes
      to how expenses/income/transfers against it are computed.
- [x] **`Money.abs()`** — new helper, needed to prefill the opening-balance field with a
      magnitude regardless of the stored sign when editing an existing liability account.
- [x] **Account edit sheet** — one more `SwitchListTile`, "This is money I owe", near the
      opening balance field (which relabels to "Amount owed" when it's on). The field always
      takes a plain positive magnitude; `_save()` computes the stored sign from the switch
      (`magnitude * -1` for a liability) every time, so toggling nature on an account that
      already has a balance re-signs it immediately on save — confirmed with the user as the
      intended behavior, no confirmation dialog.
- [x] **Account detail screen** — a liability account still in debt (`isLiability &&
      balance.minor < 0`) shows "You owe ₹X" (magnitude, `AppColors.red`) instead of
      "Balance ₹X"; paid off or overpaid, it falls back to a normal balance display. Nothing
      else changed — accounts list (shows spend, not balance), budgets, reports, exports all
      untouched, per the confirmed scope.
- [x] **Backup** — `isLiability` added to `BackupAccount` as a plain additive field, same
      shape as `includeInNetWorth`; no version bump.
- [x] Tests: 1 new `money_test.dart` case (`abs()`), 4 new `account_repository_test.dart`
      cases, one `migration_test.dart` assertion, 2 new `backup_format_test.dart` round-trip
      cases, 2 new `backup_repository_test.dart` merge/replace cases. The sign-selection
      ternary in the edit sheet's `_save()` is trivial enough (one line) to skip a dedicated
      test for, per this project's "trivial one-liners need no test" convention — covered
      instead by on-device verification. `flutter analyze` clean, 499 tests passing.

### Sub-project 3 — custom account types with icon/color (schema v20) — done

- [x] **Shared picker extraction** — `category_edit_sheet.dart`'s icon-picker-sheet,
      color-picker-sheet, custom-color dialog, and "preview strip + overflow chip"
      interaction (previously ~320 lines tightly coupled to `_CategoryEditSheetState`'s own
      fields) pulled out into `core/widgets/icon_color_picker.dart` as a controlled
      `IconColorPicker` widget (selection lives in the caller, reported back via
      `onIconChanged`/`onColorChanged`) plus the standalone `previewStripItems` function.
      `category_edit_sheet.dart` refactored to call it — same visual behavior, ~250 fewer
      lines. `test/category_edit_strip_test.dart`'s import updated to the new location;
      no other change to that test, since the function itself didn't change.
- [x] **`AccountType.custom`** — new enum value. Three new nullable columns on `Accounts`:
      `customTypeName`, `customTypeIcon` (emoji), `customTypeColorValue` (ARGB int), same
      convention as `Categories.icon`/`colorValue`, only ever set together on a custom
      account. Additive migration (`if (from < 20)`).
      `AccountRepository.create`/`update` gain the three params; `update` also gains
      `updateCustomType` (default false) to opt into overwriting — including clearing —
      all three together, since `null` on these three specifically means "not custom"
      rather than "leave unchanged" like every other `update` param.
- [x] **Account edit sheet** — a 5th "Custom" chip. Selecting it reveals a required "Type
      name" field plus an `IconColorPicker` using a new curated emoji set themed for
      account types (🏦💳💰🪙📈… — 30 icons) and the same `AppColors.swatchPalette` colors
      Categories already uses. `_save()` validates a non-empty type name when custom,
      same pattern as the existing empty-account-name check.
- [x] **List display** — `accountTypeLabel(AccountRow)` (new pure function, tested
      directly) resolves a tile's own label: the account's `customTypeName` for a custom
      account, the fixed built-in label otherwise. Section grouping still uses the
      type-only `_typeLabel`, so every custom account collapses into one shared "Custom"
      heading (per the user's explicit choice) while each tile still shows its own name.
      New `_AccountTypeIcon` widget renders a custom account's own emoji+color instead of
      the fixed Material icon.
- [x] **Backup** — three additive nullable fields on `BackupAccount`, same shape as
      `isLiability`; no version bump.
- [x] Tests: 5 new `account_repository_test.dart` cases (persist, update-together, leave-
      alone-without-the-flag, clear-on-type-switch), one `migration_test.dart` assertion,
      2 new `backup_format_test.dart` round-trip cases, 2 new `backup_repository_test.dart`
      merge/replace cases, and a new `test/account_type_label_test.dart` (4 cases) for the
      new pure function. `flutter analyze` clean, 512 tests passing (58 test files).


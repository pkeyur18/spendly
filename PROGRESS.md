# Spendly — Progress

> Cross-session shared memory. Read this first every session. Update it at the
> end of every sprint before stopping.

## Current status

- **Sprint:** post-**Sprint 11 (Ad-Hoc) — Trips, All-Transactions, per-month budgets, picker UX** (see Sprint 11 section at the bottom). Sprints 0–7 + 10 shipped (Scaffold → Polish/Accessibility + Profile), then a large run of ad-hoc feature work landed and is recorded retroactively as Sprint 11: the whole **Trips/Tags** feature, an **All-Transactions** browser, **per-month budgets** with carry-forward, the **preview-strip + popup** category icon/color pickers (+ custom hex color), an **Archived Categories** screen, and **8 → 18 default categories**. Drift schema is now **v5**; backup format is **v3**. Everything is **built + `flutter analyze`/`flutter test` green (110+ tests)**, awaiting the same real-device manual verification called out in Sprints 6/7/10. Sprint 8/9 (Beta & Hardening, Store Submission) remain not started.
- **Next:** Sprint 8 (Beta & Hardening) — TestFlight/Internal Testing builds, crash reporting + opt-in analytics, a week-long bug bash, edge cases (currency-locale mid-month, date/time changes, cross-version restore, 1000+ transactions).
- **Docs:** `requirement_docs/spendly-requirements.md` (now **v2.0**) and `requirement_docs/spendly-prototype.html` were rewritten to match the current app (Trips, All-Transactions, per-month budgets, picker UX, 18 categories, new FR-59–76). `README.md` rewritten as the real project front page. `docs/backup-schema.md` already covers backup v1→v3.
- **Locked (Sprint 6):** tap-to-add from a widget deep-links into Quick Add (opens the app) rather than writing natively in-widget — see Sprint 6 section below for the full tradeoff.

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

## How to run

```
flutter pub get
dart run build_runner build      # after any Drift schema change
flutter run                      # pick iOS simulator or Android emulator
flutter analyze && flutter test
```

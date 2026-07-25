# Spendly

**A fast, offline-first personal expense tracker for iOS & Android.** Log an expense in
seconds — from the app, a Home Screen widget, or the iOS Lock Screen — see where your money
goes through charts and reports, stay inside per-month budgets, group spending by trip, and
own a full versioned backup so your data is never truly lost.

Single codebase (Flutter), no account, no server. Money is stored as integer minor units
(paise) — never float. Currency is INR (₹) with device-locale formatting.

> **Status:** built through the ad-hoc Sprint 11 (Trips, All-Transactions, per-month
> budgets, picker UX). Drift schema v5, backup format v3, 110+ passing tests. Beta &
> hardening (Sprint 8) and store submission (Sprint 9) are not started. See
> [PROGRESS.md](PROGRESS.md) for the full sprint-by-sprint log and locked decisions.

---

## Features

- **Quick Add** — custom numeric keypad (no OS keyboard), top-8 category grid + "More"
  picker, last-used category preselected, backdate up to 90 days, optional note, optional
  trip, optional payment method.
- **Dashboard** — current-month hero card with a budget bar, category donut, 6-month trend
  bars, and recent transactions.
- **All Transactions** — full history grouped by day, month navigation, custom date range,
  multi-select category filter, lazy paging, swipe-to-delete.
- **Categories** — 18 defaults out of the box; create/rename/recolor/reorder; icon picker
  (~50 emoji) and color picker (18-swatch palette + custom hex) via a preview-strip + popup;
  archive (never lose referenced expenses) with a dedicated Archived Categories screen.
- **Budgets** — per-month overall and per-category budgets, carry-forward from the previous
  month, over-allocation warning, and 80%/100% threshold notifications.
- **Trips (Tags)** — group any expenses into a trip (holiday, wedding, project) independent
  of category, with a per-trip report and CSV/PDF export.
- **Reports** — auto-generated end-of-month report (scheduled local notification), on-demand
  custom-range reports, top-5 expenses, previous-period comparison, daily average; export as
  PDF or CSV and share via the OS share sheet.
- **Widgets** — iOS WidgetKit (Today, Quick Add, This Month, Lock Screen) + one adaptive
  Android Glance widget. Quick-add tiles deep-link into a pre-filled Quick Add
  (`spendly://quickadd?category=<id>`); read-only widgets refresh after any expense.
- **Backup & Restore** — full versioned JSON backup (expenses, categories, budgets, tags,
  settings, profile), optional AES-256-GCM password protection, save-to-cloud via the OS
  share sheet, auto-backup (daily/weekly/monthly), and restore with a preview + Merge/Replace
  choice. See [docs/backup-schema.md](docs/backup-schema.md).
- **Profile** — name/email/phone, avatar (uploaded photo or colored initials — never a blank
  state), lifetime stats, theme, and a backup-gated "Delete all data".
- **Onboarding** — one-time name-gated welcome screen; the app routes to Home once a name exists.
- **Accessibility & theming** — full light/dark (system default + manual override, 400ms
  crossfade), Dynamic Type, VoiceOver/TalkBack labels including chart summaries, and color is
  never the only signal.

---

## Tech stack

| Concern | Choice |
|---|---|
| UI / framework | Flutter (Dart) |
| State | Riverpod (`flutter_riverpod`) |
| Local DB | Drift (SQLite), schema v5 — money as integer minor units |
| Charts | `fl_chart` |
| Notifications | `flutter_local_notifications` + `timezone` / `flutter_timezone` |
| Reports/export | `pdf`, hand-written RFC-4180 CSV, `share_plus` |
| Backup crypto | `cryptography` (AES-256-GCM + PBKDF2) |
| Widgets bridge | `home_widget` → native Swift/WidgetKit (iOS) & Kotlin/Glance (Android) |
| Media / files | `image_picker`, `file_picker`, `flutter_colorpicker`, `path_provider` |

Fonts (bundled offline): **Sora** (display) + **Inter** (body). Brand palette: indigo → pink
(`#6366F1` → `#EC4899`).

> Several dependencies are **deliberately pinned** (`file_picker 10.3.10`, `share_plus ^12`)
> for Android toolchain reasons, and iOS deployment target is **26.0** by explicit choice
> (real floor is iOS 14). Read the **Stack / tooling** section of [PROGRESS.md](PROGRESS.md)
> before bumping anything native.

---

## Project layout

```
lib/
├── main.dart · app.dart            # boot + root routing (onboarding vs home), lifecycle hooks
├── core/
│   ├── db/                         # Drift database, schema/migrations, row extensions
│   ├── money/                      # integer-minor-unit Money type + locale formatting
│   ├── notify/                     # local notifications (budget alerts, monthly report)
│   ├── theme/                      # tokens, light/dark ThemeData
│   └── widgets/                    # shared UI (keypad, cards, async states, glyphs)
└── features/
    ├── onboarding/                 # welcome screen
    ├── home/                       # dashboard + charts + providers
    ├── expenses/                   # quick add, all-transactions, repository, recurrence
    ├── categories/                 # manager, edit sheet (strip+popup), archived
    ├── budgets/                    # per-month budget setup + repository
    ├── reports/                    # monthly/custom reports, export (PDF/CSV)
    ├── tags/                       # trips: manager, edit, per-trip reports
    ├── profile/                    # profile hub, edit, avatar picker, lifetime stats
    ├── backup/                     # backup/restore, crypto, format, auto-backup
    ├── widgets/                    # home-widget snapshot + refresh bridge
    └── settings/                   # theme mode provider

ios/SpendlyWidget/                  # Swift WidgetKit extension (4 widget variants)
android/app/src/main/kotlin/.../widget/   # Kotlin Glance widget + receiver
docs/backup-schema.md               # versioned backup file format (v1→v3)
requirement_docs/                   # requirements + interactive prototype
test/                               # 29 test files (money, repos, backup, reports, …)
```

---

## Getting started

```bash
flutter pub get
dart run build_runner build      # regenerate Drift code after any schema change
flutter run                      # pick an iOS simulator or Android emulator
flutter analyze && flutter test  # 110+ tests
```

The DB (`spendly.sqlite`) is created on first launch in the app documents directory and
seeded with 18 default categories. No configuration or account is required.

---

## Documentation

- 📋 **[Product Requirements](requirement_docs/spendly-requirements.md)** — full functional
  (FR-*) and non-functional spec, information architecture, screen list.
- 🎨 **[Interactive Prototype](requirement_docs/spendly-prototype.html)** — clickable
  mockups of every screen in light & dark themes (open in a browser).
- 💾 **[Backup Schema](docs/backup-schema.md)** — the versioned JSON backup file format and
  Merge/Replace algorithms.
- 📈 **[PROGRESS.md](PROGRESS.md)** — sprint-by-sprint build log, locked decisions, and
  dependency/native-build notes.

---

## Key decisions

- **Single currency (INR ₹)** with locale formatting; multi-currency is a v2 candidate.
- **Offline-first, no backend.** Cloud "sync" is share-sheet save/restore only — no account.
- **Recurring expenses remind, never auto-log** — the user confirms on the due date.
- **Backups are optionally password-protected** (AES-256-GCM + PBKDF2), per the user's choice.
- **Auto-backup runs on app launch/resume** (no background service), default weekly.

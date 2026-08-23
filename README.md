# Spendly

**A fast, offline-first personal expense tracker for iOS & Android.** Log an expense in
seconds — from the app, a Home Screen widget, or the iOS Lock Screen — see where your money
goes through charts and reports, stay inside per-month budgets, group spending by trip, and
own a full versioned backup so your data is never truly lost.

Single codebase (Flutter), no account, no server. Money is stored as integer minor units
(paise) — never float. Currency is INR (₹) with device-locale formatting.

> **Status:** built through UX-enhancement phases 1–4 (daily-loop friction fixes,
> recurring expenses, receipt photos, accounts), on top of Sprint 12 and the Monthly
> Recap feature. Drift schema v12, backup format v8, 389 passing tests (51 test
> files). Beta & hardening (Sprint 8) and store submission (Sprint 9) are not
> started. See [PROGRESS.md](PROGRESS.md) for the full sprint-by-sprint log and
> locked decisions.

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
  month, over-allocation warning, 80%/100% threshold notifications, and a per-category
  "ignore in totals" toggle for fixed costs (rent, EMI) — excluded from daily totals, budget
  math, top categories, and top expenses, while still tracked on its own budget card and
  still visible in All Transactions and exports.
- **Trips (Tags)** — group any expenses into a trip (holiday, wedding, project) independent
  of category, with a per-trip report and CSV/PDF export.
- **Reports** — auto-generated end-of-month report (scheduled local notification), on-demand
  custom-range reports, top-5 expenses, previous-period comparison, daily average; export as
  PDF or CSV and share via the OS share sheet.
- **Monthly Recap** — a full-screen "hero" takeover auto-shown once per new month on app
  launch/resume (skipped on fresh installs with no prior-month expenses; gated by a
  persisted last-shown-month flag): a gradient hero card ("you saved this month" with a
  falling-emoji confetti overlay, "you went over budget" in amber, or a plain total if no
  budget is set) plus a top-3 spending categories card. Also reachable any time via a
  permanent "Monthly recap" row in Profile.
- **Recurring expenses** — mark any expense daily/weekly/monthly with an optional end
  date; the app reminds on the due date and the user confirms, never auto-logs (FR-7).
  Occurrences missed while the app was closed are all recovered, each confirmed or
  skipped on its own, and a month-end series stays pinned to its day instead of drifting
  onto the 28th after February. A "payments to confirm" card appears on Home only when
  something is due; a permanent "Recurring expenses" row in Profile manages every series.
- **Receipt photos** — attach a photo (camera or library) to any expense from Quick Add;
  view, replace, or remove it any time. Stored in its own table, separate from the
  expense row itself, so browsing transactions never has to load photo bytes it isn't
  showing. Travels in full-fidelity backups; a device restoring a backup gets every
  attached photo back, correctly matched to its own expense.
- **Accounts** — track cash, bank, card and wallet balances; pick which account an expense
  was paid from in Quick Add, with a per-account current-month spend view under Profile.
  Never hard-deleted — archived like categories/tags, so history and exports stay intact.
  An account has no icon/color of its own; the free-text `paymentMethod` field expenses
  already carried is migrated into real accounts automatically on upgrade, preserved either
  way.
- **Widgets** — iOS WidgetKit (Today, Quick Add, This Month, Lock Screen) + one adaptive
  Android Glance widget. Quick-add tiles deep-link into a pre-filled Quick Add
  (`spendly://quickadd?category=<id>`); read-only widgets refresh after any expense.
- **Backup & Restore** — full versioned JSON backup (expenses, categories, budgets, tags,
  accounts, settings, profile), optional AES-256-GCM password protection, save-to-cloud via the OS
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
| Local DB | Drift (SQLite), schema v12 — money as integer minor units |
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
    ├── accounts/                   # cash/bank/card/wallet accounts, manage screen
    ├── categories/                 # manager, edit sheet (strip+popup), archived
    ├── budgets/                    # per-month budget setup + repository
    ├── reports/                    # monthly/custom reports, export (PDF/CSV)
    ├── recap/                      # monthly recap: auto-shown summary + manual replay from Profile
    ├── tags/                       # trips: manager, edit, per-trip reports
    ├── profile/                    # profile hub, edit, avatar picker, lifetime stats
    ├── backup/                     # backup/restore, crypto, format, auto-backup
    ├── widgets/                    # home-widget snapshot + refresh bridge
    ├── settings/                   # theme mode provider
    └── dev/                        # debug data screen (dev-only tooling)

ios/SpendlyWidget/                  # Swift WidgetKit extension (4 widget variants)
android/app/src/main/kotlin/.../widget/   # Kotlin Glance widget + receiver
docs/architecture.md                # arc42 architecture doc
docs/adr/                           # 9 architecture decision records
docs/known-issues.md                # known-issues ledger
docs/backup-schema.md               # versioned backup file format (v1→v3)
docs/requirement_docs/              # requirements + interactive prototype
test/                               # 37 test files (money, repos, backup, reports, recap, …)
```

---

## Getting started

```bash
flutter pub get
dart run build_runner build      # regenerate Drift code after any schema change
flutter run                      # pick an iOS simulator or Android emulator
flutter analyze && flutter test  # 190 tests
```

The DB (`spendly.sqlite`) is created on first launch in the app documents directory and
seeded with 18 default categories. No configuration or account is required.

---

## Documentation

- 📋 **[Product Requirements](docs/requirement_docs/spendly-requirements.md)** — full functional
  (FR-*) and non-functional spec, information architecture, screen list.
- 🎨 **[Interactive Prototype](docs/requirement_docs/spendly-prototype.html)** — clickable
  mockups of every screen in light & dark themes (open in a browser).
- 🏛️ **[Architecture](docs/architecture.md)** — arc42-format architecture overview.
- 🧭 **[ADRs](docs/adr/)** — 9 architecture decision records (feature-first structure,
  Riverpod state/DI, Drift local persistence, no-cloud-sync, widget-bridge shared storage,
  push-based widget refresh, imperative navigation, money/currency model, testing strategy).
- ⚠️ **[Known Issues](docs/known-issues.md)** — ledger of known gaps/limitations.
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
- **Categories and expenses carry a stable `externalId`** (since schema v7), independent of the
  local row ID, used to match records across devices during a backup Merge.

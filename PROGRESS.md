# Spendly — Progress

> Cross-session shared memory. Read this first every session. Update it at the
> end of every sprint before stopping.

## Current status

- **Sprint:** 0 (Project Setup) — **built, awaiting user verification**
- **Next:** Sprint 1 (Core Data Layer) — do NOT start until user gives go.

## Locked decisions (from PRD open questions)

- **Currency:** single currency; symbol + number format follow device locale, default ₹ INR. Multi-currency = v2. (PRD Q1)
- **Recurring (FR-7):** remind + user confirms on due date via local notification; never silent auto-log. (PRD Q3)
- **State management:** Riverpod (`flutter_riverpod`).
- **Local DB:** Drift (SQLite). Money stored as **integer minor units** (paise), never float.
- Still open, resolve before Sprint 5: cloud-sync scope (Q2), backup encryption (Q6), auto-backup default frequency (Q7).

## Stack / tooling

- Flutter 3.44.5 · Dart 3.12.2 · Xcode 26.6 · Android SDK · CocoaPods (all verified present).
- Deps: flutter_riverpod, drift + sqlite3_flutter_libs + path_provider + path, intl, fl_chart. Dev: drift_dev, build_runner, flutter_lints.
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

## How to run

```
flutter pub get
dart run build_runner build      # after any Drift schema change
flutter run                      # pick iOS simulator or Android emulator
flutter analyze && flutter test
```

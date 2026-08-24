# Dark Premium Redesign — Design Spec

Date: 2026-08-24
Status: Presented to user, pending review before implementation plan.

## Scope

**UI/UX only.** No schema, repository, provider, or business-logic changes.
Every screen keeps its current data, queries, and behavior; only visuals
change, except the one explicitly-approved pattern change (Transfer Money,
see below) and the one explicitly-approved UI-layer feature (Income
month/year toggle, see below) — both are presentation-layer only, no new
persistence or query beyond an existing unused repository method.

The app is redesigned to a single dark "glass premium" visual language and
**light mode is removed entirely** — no theme toggle, no `ThemeMode.system`
following. This covers every in-app surface: screens, shared components,
SnackBars, AlertDialogs, native date/time pickers, loading/error/empty
states, and the once-a-month Recap hero. It does not cover OS-level surfaces
Flutter's theme system can't reach — system push-notification banner
styling, the `home_widget` home-screen widget, or the app icon/splash screen
— those are out of scope; flag separately if wanted later.

## Direction: Dark Premium

Established during brainstorming as one of four comparable mockup
directions (see `redesign-board` artifact), picked by user for all 8
originally-scoped screens and now extended app-wide.

- **Surface**: near-black base (`#0B0B10`), frosted/translucent glass cards
  (`rgba(255,255,255,.06)` + backdrop blur, `rgba(255,255,255,.12)` hairline
  border) rather than flat opaque cards.
- **Accent**: gold/champagne (`#D8B26A`) + violet (`#7C5CFF`) gradient,
  replacing today's indigo/pink `brandGradient`. Category swatch palette
  (`AppColors` teal/red/green/etc.) is unaffected — those are user-facing
  category colors, not theme chrome.
- **Type**: Sora (headings/money, tight tracking) + Inter (body) — same
  families as today, so no new font assets; weight/scale tuned for the
  darker, higher-contrast ground.
- **Radius/shadow**: slightly larger corner radius than today's tokens,
  soft deep shadows (`0 18-24px 40-50px rgba(0,0,0,.5)`) for elevation on a
  dark ground where a light drop-shadow would be invisible.

## Theme foundation (`lib/core/theme/`)

Audit confirmed this is a clean, contained change — zero scattered
light-only reads outside the theme files themselves.

- `tokens.dart`: delete `AppPalette.light`; replace `AppPalette.dark`'s
  values with the Dark Premium palette above. `AppColors` brand-independent
  constants (category swatches, `heroGradient`/`brandGradient`) updated to
  the new accent gradient; category swatch colors unchanged.
- `app_theme.dart`: `_build(Brightness)` collapses to a single build path
  (brightness argument removed or hardcoded). `AppTheme.light()` deleted;
  `AppTheme.dark()` is the one surviving factory (may rename to
  `AppTheme.premium()` — implementation plan's call).
- Add explicit `SnackBarThemeData`, `DialogThemeData`, and
  `DatePickerThemeData`/`TimePickerThemeData` to the built `ThemeData` so
  SnackBars, AlertDialogs, and native pickers pick up glass/dark styling
  automatically rather than falling back to Material defaults — this is
  what makes "toasts and messages uniform too" true by construction instead
  of per-call-site work.
- `lib/app.dart`: `MaterialApp(theme: AppTheme.dark())`; drop `darkTheme:`
  and `themeMode:` params, and the `AnimatedTheme` brightness-crossfade
  wrapper (dead once there is one theme). Drop the `ThemeMode.system`
  fallback reference near the profile-async watch.
- Delete `lib/features/settings/theme_mode_provider.dart`. Remove the one
  stray reference: `delete_all_data_flow.dart:36`
  (`ref.invalidate(themeModeProvider)`).
- `profile_screen.dart:141-150` (Theme menu row) and `:259-306`
  (`_themeLabel`/`_openThemePicker`) deleted — this is the only
  user-facing settings UI affected by the light-mode removal.
- `SettingsRepository.themeModeKey` persistence key becomes dead; drop it
  as part of cleanup (low risk, no migration needed — an unread key is
  harmless either way, but leaving it is untidy).
- `test/app_theme_test.dart`: delete the light-dialog test case (`:6-13`),
  point the remaining case at the surviving factory.

## Shared components (restyle once, most of the app inherits it)

`lib/core/widgets/`: `AppCard`/`SectionTitle`, `AmountKeypad`/
`AmountDisplay`, `LoadingView`/`ErrorView`/`EmptyView`, `RepeatPickerSheet`,
`IconColorPicker`, `CategoryGlyph`. Plus the bottom-sheet boilerplate
pattern shared by every add/edit flow, and `AppShell`'s bottom nav + docked
FAB (`lib/features/home/app_shell.dart`) — nav colors already come from
`AppPalette.navBackground`/`navIconInactive`/`navBorder`, so this is a
palette-value change, not a structural one.

Every screen that composes these (which is most of the app) inherits the
glass/dark look without a per-screen edit once this layer and the theme
foundation are done. Per-screen work after this point is about layout and
content, not base color/type.

## Per-screen scope

**8 screens with approved mockups** (visual reference: `redesign-board`
artifact, Direction D): Transfer Money, Edit Account, Add Account, New
Expense, Recurring, Income, Add Income, New Savings Goal.

- **Transfer Money — pattern change, approved.** Becomes a full screen
  (not a bottom sheet): two account cards, swap affordance, amount, then a
  review step — per the D mockup. This is the one screen whose interaction
  shape changes; every other screen keeps its current sheet/full-screen
  pattern, restyled in place.
- **Income — month/year toggle, approved, no architecture gap.**
  `LedgerRepository.watchInRange` already exists and is unused; the
  month/current-year grouping is a UI-layer transform over its result. No
  new query or schema work.
- **Add Income** — same sheet also serves Edit and "confirm a due
  recurring occurrence" (`showIncomeConfirmSheet`); one restyle covers all
  three modes, only copy/badge differs.
- **Edit Account / Add Account** — one component (`_AccountEditSheet`,
  `existing` flag); one restyle covers both.

**Chart screens** (recolor `fl_chart` series/donut/bar colors to the new
palette; layout otherwise inherits from shared components): Home dashboard
(`home_screen.dart` — spend donut, trend bars), `MonthlyReportScreen`,
`CustomReportScreen`, `TagReportScreen`/`TagDetailScreen` (all reuse
`ReportHero`/donut in `report_widgets.dart`), `InsightsScreen`.

**Monthly Recap** (`monthly_recap_screen.dart`) — reskinned to the Dark
Premium accent palette, per user's explicit call; animation/confetti
behavior unchanged.

**Remaining screens** (inherit shared-component styling; touched mainly for
layout/spacing polish, no bespoke mockup): `AccountDetailScreen`,
`AllTransactionsScreen` (+ its category filter sheet), `BudgetSetupScreen`,
`CategoryManagerScreen`, `ArchivedCategoriesScreen`, `CategoryEditSheet`,
`TagManagerScreen`, `TagEditSheet`, `CurrencyPickerScreen`,
`BackupRestoreScreen`, `RestoreScreen`, `AppLockScreen`, `WelcomeScreen`,
`ProfileScreen`, `EditProfileScreen`, `AvatarPickerScreen`.

`DebugDataScreen` (`lib/features/dev/`) is `kDebugMode`-gated dev-only
tooling — excluded from the redesign.

## Rollout order

1. Theme foundation + shared components — recolors ~80% of the app
   immediately, before any per-screen layout work starts.
2. The 8 mockup'd screens (includes the one pattern change and the income
   toggle).
3. Chart screens (palette-only `fl_chart` recolor).
4. Monthly Recap.
5. Remaining ~16 list/detail/form screens.

Each batch should be independently shippable and testable — the
implementation plan (next step, via writing-plans) will turn this into
concrete phases with file-level tasks.

## Out of scope / explicit non-goals

- No backend, schema, repository, or business-logic changes anywhere.
- No OS-level theming (push notification banners, home-screen widget, app
  icon/splash).
- `DebugDataScreen` untouched.
- Category swatch colors (user-chosen per category/account) unchanged —
  only theme chrome (surfaces, accents, nav, buttons) changes.

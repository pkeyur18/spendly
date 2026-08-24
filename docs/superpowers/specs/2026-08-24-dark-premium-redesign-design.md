# Dark Premium Redesign — Design Spec

Date: 2026-08-24
Status: Presented to user, pending review before implementation plan.

**Revision (same day):** the original plan removed light mode and repainted
the app's brand colors to gold/violet. User reversed that after seeing
Phase 1 implemented — theme (light+dark toggle, indigo/pink brand colors,
Profile's Theme setting) is **restored exactly as it was**; see the "Theme
foundation" section below, now much smaller. The glass-card visual
treatment and every per-screen layout change are kept, just built on top of
the existing two-theme system instead of replacing it.

## Scope

**UI/UX only.** No schema, repository, provider, or business-logic changes.
Every screen keeps its current data, queries, and behavior; only visuals
change, except the one explicitly-approved pattern change (Transfer Money,
see below) and the one explicitly-approved UI-layer feature (Income
month/year toggle, see below) — both are presentation-layer only, no new
persistence or query beyond an existing unused repository method.

The app keeps its **existing light and dark themes and the theme-mode
toggle**, unchanged. What's redesigned is the component/layout language on
top: glass/frosted cards, revised spacing and hierarchy, and the per-screen
layout changes below — applied consistently across both themes. This
covers every in-app surface: screens, shared components, SnackBars,
AlertDialogs, native date/time pickers, loading/error/empty states, and the
once-a-month Recap hero — each themed correctly in both light and dark. It
does not cover OS-level surfaces Flutter's theme system can't reach —
system push-notification banner styling or the app icon/splash screen;
those stay out of scope. The home-screen widget is discussed in its own
section below — see that section for why it now needs little to no change.

## Direction: Glass, on both themes

Established during brainstorming as one of four comparable mockup
directions (see `redesign-board` artifact, "Dark Premium" / Direction D),
picked by user for all 8 originally-scoped screens and extended app-wide —
**with its color identity reverted to the app's existing indigo/pink
brand** rather than the gold/violet built for the dark-only version.

- **Surface**: cards become translucent/frosted rather than flat opaque —
  a low-opacity tint of the theme's existing card color plus backdrop blur,
  over the theme's existing background, not a new fixed dark ground. In
  dark theme this looks like the original mockup (frosted glass over
  near-black); in light theme it's the same technique over the light
  background — frosted glass over `#F5F5F7`, still legible, less "premium
  moody," more "soft glass." Both are real, both get equal polish.
- **Accent**: unchanged — `AppColors.primary` (indigo `#6366F1`) /
  `AppColors.pink` (`#EC4899`) and the existing `brandGradient`/
  `heroGradient`. No new brand colors. Category swatch palette is
  unaffected either way — those are user-facing category colors, not
  theme chrome.
- **Type**: Sora (headings/money) + Inter (body) — unchanged, no new font
  assets.
- **Radius/shadow**: slightly larger corner radius than today's tokens
  (kept from the original mockup direction), shadow tuned per theme — a
  soft dark shadow reads fine on light, but needs to be a glow/lighter
  border-emphasis on dark where a black drop-shadow disappears.

## Theme foundation (`lib/core/theme/`)

**Nothing here is deleted.** `AppColors`, `AppPalette.light`/`.dark`,
`AppTheme.light()`/`.dark()`, the `themeModeProvider` toggle, and Profile's
Theme setting all stay exactly as they are today — reverted back after
Phase 1 was tried and reversed.

What's *added*, additively, on both `AppPalette.light` and
`AppPalette.dark`:

- New `AppPalette` fields for the glass treatment — a translucent card
  color (existing card color at low opacity, tuned separately per theme
  since the right opacity for "frosted" differs on a white vs. near-black
  ground) and a hairline glass-border color. Implementation plan decides
  exact field names/values; the two existing static consts (`.light`/
  `.dark`) each grow these new fields, nothing removed.
- A shared blur-sigma constant for `BackdropFilter` (same value both
  themes — blur amount doesn't need to differ, only the tint under it
  does).
- `SnackBarThemeData`, `DialogThemeData` (already exists, unchanged
  structurally), and `DatePickerThemeData`/`TimePickerThemeData` added to
  `_build(Brightness)` for **both** branches, each themed against that
  branch's own palette — this is what makes "toasts and messages uniform
  too" true in both light and dark, by construction rather than
  per-call-site work.
- `AppRadius.card`/`AppRadius.button` bumped slightly larger (brightness-
  independent, no light/dark split needed there).

No files are deleted in this phase. `test/app_theme_test.dart` gains cases
for the new light+dark SnackBar/DatePicker/TimePicker theming; its existing
light/dark dialog cases are untouched.

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

**Monthly Recap** (`monthly_recap_screen.dart`) — reskinned to the glass
treatment (both themes), per user's explicit call; animation/confetti
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

## Home-screen widget (native, not Flutter) — mostly a no-op now

`home_widget` bridges the app to a fully **native** widget UI — Dart only
writes string/number data (`lib/features/widgets/widget_snapshot.dart`,
`WidgetBridge.write`); colors and layout live entirely in platform code.

- **iOS**: `ios/SpendlyWidget/SpendlyWidget.swift:10-11` — the brand colors
  are indigo `#6366F1` / pink `#EC4899`, composed into a `brandGradient`
  used as each widget's background. **These already match the app's
  (unchanged) brand colors** — since the accent reverted to indigo/pink
  instead of moving to gold/violet, no color edit is needed here.
- **Android**: `android/app/src/main/kotlin/com/spendly/spendly/widget/SpendlyGlanceWidget.kt:39` —
  same situation, the `indigo` `ColorProvider` already matches.
- Optional, not required: if a frosted/glass look is wanted on the widget's
  inner elements to visually rhyme with the in-app glass cards, both files
  already have a `Color.white.opacity(0.18)` translucent-chip treatment for
  inner elements (`SpendlyWidget.swift`) — leave as-is unless asked for
  more. WidgetKit/Glance materials (native blur) are a platform-specific
  can of worms disproportionate to the payoff here; not recommended.
- **Net effect: this item drops out of the rollout as a required task.**
  Revisit only if, after seeing the in-app glass cards, the native widget
  looks visually behind — that's a call to make by eye once the rest is
  built, not something to plan blind now.

## Rollout order

1. Theme foundation (glass tokens, both themes) + shared components — gives
   ~80% of the app the glass look immediately, in both light and dark,
   before any per-screen layout work starts.
2. The 8 mockup'd screens (includes the one pattern change and the income
   toggle), each verified in both themes.
3. Chart screens (`fl_chart` colors already match brand — mainly checking
   the new card/surface treatment reads correctly behind charts in both
   themes).
4. Monthly Recap.
5. Remaining ~16 list/detail/form screens.

Home-screen widget dropped from the required rollout — see its section
above.

Each batch should be independently shippable and testable, **and each must
be checked in both light and dark** (this doubles the manual-verification
surface per phase compared to the dark-only plan — worth calling out
explicitly since it's the main cost of this revision).

## Out of scope / explicit non-goals

- No backend, schema, repository, or business-logic changes anywhere.
- No OS-level theming — push notification banners, app icon/splash, and
  (per the section above) the home-screen widget's colors stay untouched.
- `DebugDataScreen` untouched.
- Category swatch colors (user-chosen per category/account) unchanged —
  only theme chrome (surfaces, accents, nav, buttons) changes.
- No brand color change — indigo/pink stays; the gold/violet Dark Premium
  palette from the original plan is abandoned.

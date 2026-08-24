# Dark Premium Redesign — Phase 1: Theme Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's light+dark theme pair with a single "Dark Premium"
dark theme (gold/violet accent, near-black surfaces), remove the light-mode
toggle end to end, and make SnackBars/dialogs/date-time pickers uniformly
themed — the foundation every later screen-restyle phase builds on.

**Architecture:** `tokens.dart`'s `AppColors`/`AppPalette` are the single
source of color truth (confirmed: zero call sites read `AppColors.light*`/
`AppColors.dark*` directly, everything goes through `AppPalette` or the
brand constants) — so recoloring is contained to the two theme files plus
deleting the settings plumbing that made light mode reachable. No widget
outside `lib/core/theme/` needs a code change for the palette swap itself.

**Tech Stack:** Flutter (Material 3), Riverpod, existing `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-24-dark-premium-redesign-design.md`
(see "Theme foundation" section)

## Global Constraints

- UI-only. No schema, repository, or provider logic changes beyond deleting
  the now-dead `themeModeProvider` and its one persisted settings key.
- Keep existing token/class names (`AppColors`, `AppPalette`, `AppTheme`,
  `AppRadius`, `AppSpacing`) — this is a value swap, not a rename, so every
  existing call site (25 files reference `AppColors.primary` directly, 13
  reference `brandGradient`) keeps working unchanged.
- New palette values (exact, from the spec's Direction D mockup):
  - `primaryDeep` (deep gold) `#A97D3E`, `primary` (gold/champagne)
    `#D8B26A`, `primarySoft` (light gold) `#E8CDA0`.
  - `pink` (now violet — name kept for diff minimalism, see code comment)
    `#7C5CFF`, `pinkLight` (light violet) `#A78BFA`.
  - `darkBg` `#0B0B10`, `darkCard` `#17151F`, `darkCard2` `#1D1A29`,
    `darkText` `#F5F4F7`, `darkTextDim` `#96939F`.
  - `darkLine` becomes translucent white `Color(0x21FFFFFF)` (13% white) —
    this alone gives cards a glass-hairline edge even before Phase 2 adds
    real blur.
  - `navBgDark` `#15121F`, `navIconOffDark` `#8A85A6`, `navBorder` stays
    `Color(0x14FFFFFF)`.
  - `AppRadius.card` `22 → 26`, `AppRadius.button` `16 → 18` (hero/icon
    unchanged).
  - **Not touched:** `AppColors.accent` (amber — semantic warning color,
    not brand chrome), `teal`/`red`/`green` (semantic income/expense/status
    colors), `swatchPalette` (user-chosen category colors). The spec is
    explicit these are unaffected by the theme-chrome change.

---

### Task 1: Dark Premium color tokens

**Files:**
- Modify: `lib/core/theme/tokens.dart`
- Test: `test/tokens_test.dart` (new)

**Interfaces:**
- Produces: `AppColors.{primary,primarySoft,primaryDeep,pink,pinkLight,darkBg,darkCard,darkCard2,darkText,darkTextDim,darkLine,navBgDark,navIconOffDark}` (all `Color`, existing names, new values), `AppColors.heroGradient`/`brandGradient` (existing `LinearGradient` getters, recolored), `AppPalette.dark` (existing static const, new values), `AppRadius.card`/`AppRadius.button` (existing `double` consts, new values). `AppColors.lightBg`/`lightCard`/`lightCard2`/`lightText`/`lightTextDim`/`lightLine`/`navBgLight`/`navIconOffLight` and `AppPalette.light` are **deleted** — Task 2 depends on this deletion to force the theme-builder simplification.

- [ ] **Step 1: Write the failing test**

Create `test/tokens_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/theme/tokens.dart';

void main() {
  group('AppColors — Dark Premium palette', () {
    test('brand gold/violet family', () {
      expect(AppColors.primary, const Color(0xFFD8B26A));
      expect(AppColors.primarySoft, const Color(0xFFE8CDA0));
      expect(AppColors.primaryDeep, const Color(0xFFA97D3E));
      expect(AppColors.pink, const Color(0xFF7C5CFF));
      expect(AppColors.pinkLight, const Color(0xFFA78BFA));
    });

    test('dark surfaces', () {
      expect(AppColors.darkBg, const Color(0xFF0B0B10));
      expect(AppColors.darkCard, const Color(0xFF17151F));
      expect(AppColors.darkCard2, const Color(0xFF1D1A29));
      expect(AppColors.darkText, const Color(0xFFF5F4F7));
      expect(AppColors.darkTextDim, const Color(0xFF96939F));
      expect(AppColors.darkLine, const Color(0x21FFFFFF));
    });

    test('nav surface', () {
      expect(AppColors.navBgDark, const Color(0xFF15121F));
      expect(AppColors.navIconOffDark, const Color(0xFF8A85A6));
    });

    test('brandGradient is gold-to-violet', () {
      expect(AppColors.brandGradient.colors, [
        AppColors.primary,
        AppColors.pink,
      ]);
    });

    test('heroGradient is deep-gold to gold to violet', () {
      expect(AppColors.heroGradient.colors, [
        AppColors.primaryDeep,
        AppColors.primary,
        AppColors.pink,
      ]);
    });
  });

  group('AppPalette.dark', () {
    test('matches the new dark tokens', () {
      expect(AppPalette.dark.card, AppColors.darkCard);
      expect(AppPalette.dark.card2, AppColors.darkCard2);
      expect(AppPalette.dark.textDim, AppColors.darkTextDim);
      expect(AppPalette.dark.line, AppColors.darkLine);
      expect(AppPalette.dark.navBackground, AppColors.navBgDark);
      expect(AppPalette.dark.navIconInactive, AppColors.navIconOffDark);
    });
  });

  group('AppRadius', () {
    test('card and button are the Dark Premium sizes', () {
      expect(AppRadius.card, 26.0);
      expect(AppRadius.button, 18.0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tokens_test.dart`
Expected: FAIL — every `expect` mismatches today's indigo/pink values
(e.g. `AppColors.primary` is currently `Color(0xFF6366F1)`, not
`Color(0xFFD8B26A)`).

- [ ] **Step 3: Replace `lib/core/theme/tokens.dart` with the Dark Premium version**

```dart
import 'package:flutter/material.dart';

/// Design tokens. Single source of truth for color, spacing, radius, type.
/// Do not hardcode hex/sizes in widgets — reference these.
///
/// Dark Premium palette (2026-08-24 redesign): the app is dark-only, no
/// light theme. `pink`/`pinkLight` names are kept from the prior
/// indigo/pink brand pair for diff minimalism even though their values are
/// now violet — the gradient role (paired accent) is what the name tracks,
/// not the literal hue.
class AppColors {
  AppColors._();

  // Brand (theme-independent) — gold/champagne + violet
  static const primary = Color(0xFFD8B26A);
  static const primarySoft = Color(0xFFE8CDA0);
  static const primaryDeep = Color(0xFFA97D3E);
  static const accent = Color(0xFFF59E0B);
  static const pink = Color(0xFF7C5CFF);
  static const teal = Color(0xFF14B8A6);
  static const red = Color(0xFFEF4444);
  static const green = Color(0xFF22C55E);

  // Gradient companions (paired with a brand color above, never used alone)
  static const amberDeep = Color(0xFFEA580C);
  static const amberDeeper = Color(0xFFB45309);
  static const tealDeep = Color(0xFF0D9488);
  static const pinkLight = Color(0xFFA78BFA);

  // Dark surfaces (the only theme — see AppTheme)
  static const darkBg = Color(0xFF0B0B10);
  static const darkCard = Color(0xFF17151F);
  static const darkCard2 = Color(0xFF1D1A29);
  static const darkText = Color(0xFFF5F4F7);
  static const darkTextDim = Color(0xFF96939F);
  static const darkLine = Color(0x21FFFFFF);

  // Bottom nav (own violet-black surface, distinct from card)
  static const navBgDark = Color(0xFF15121F);
  static const navIconOffDark = Color(0xFF8A85A6);

  /// Hero / FAB / primary-button gradient (135deg deep gold → gold → violet).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, primary, pink],
  );

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, pink],
  );

  /// Curated swatches for color pickers (categories, tags) — distinct hues
  /// so items stay visually distinguishable even with many of them. NOT
  /// part of the theme-chrome redesign: these are user-chosen colors.
  static const swatchPalette = [
    Color(0xFF3B82F6), // blue
    Color(0xFF6366F1), // indigo
    Color(0xFF8B5CF6), // violet
    Color(0xFFA855F7), // purple
    Color(0xFFD946EF), // fuchsia
    Color(0xFFEC4899), // pink
    Color(0xFFF43F5E), // rose
    Color(0xFFEF4444), // red
    Color(0xFFF97316), // orange
    Color(0xFFF59E0B), // amber
    Color(0xFFEAB308), // yellow
    Color(0xFF84CC16), // lime
    Color(0xFF22C55E), // green
    Color(0xFF10B981), // emerald
    Color(0xFF14B8A6), // teal
    Color(0xFF06B6D4), // cyan
    Color(0xFF0EA5E9), // sky
    Color(0xFF64748B), // slate
  ];
}

/// Extra semantic colors not expressible in ColorScheme, read via
/// `Theme.of(context).extension<AppPalette>()`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.card,
    required this.card2,
    required this.textDim,
    required this.line,
    required this.navBackground,
    required this.navIconInactive,
    required this.navBorder,
  });

  final Color card;
  final Color card2;
  final Color textDim;
  final Color line;
  final Color navBackground;
  final Color navIconInactive;
  final Color navBorder;

  static const dark = AppPalette(
    card: AppColors.darkCard,
    card2: AppColors.darkCard2,
    textDim: AppColors.darkTextDim,
    line: AppColors.darkLine,
    navBackground: AppColors.navBgDark,
    navIconInactive: AppColors.navIconOffDark,
    navBorder: Color(0x14FFFFFF),
  );

  @override
  AppPalette copyWith({
    Color? card,
    Color? card2,
    Color? textDim,
    Color? line,
    Color? navBackground,
    Color? navIconInactive,
    Color? navBorder,
  }) {
    return AppPalette(
      card: card ?? this.card,
      card2: card2 ?? this.card2,
      textDim: textDim ?? this.textDim,
      line: line ?? this.line,
      navBackground: navBackground ?? this.navBackground,
      navIconInactive: navIconInactive ?? this.navIconInactive,
      navBorder: navBorder ?? this.navBorder,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      card: Color.lerp(card, other.card, t)!,
      card2: Color.lerp(card2, other.card2, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      line: Color.lerp(line, other.line, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      navIconInactive: Color.lerp(navIconInactive, other.navIconInactive, t)!,
      navBorder: Color.lerp(navBorder, other.navBorder, t)!,
    );
  }
}

/// 8pt-ish spacing rhythm from the prototype.
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

class AppRadius {
  AppRadius._();
  static const chip = 100.0;
  static const card = 26.0;
  static const hero = 26.0;
  static const button = 18.0;
  static const icon = 13.0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tokens_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Confirm nothing else in the repo referenced the deleted light tokens**

Run: `grep -rn "AppColors\.light\|AppPalette\.light" lib/ test/`
Expected: no output. (The design-spec audit already confirmed this before
the change; this just re-verifies after editing.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/tokens.dart test/tokens_test.dart
git commit -m "feat: swap theme tokens to Dark Premium gold/violet palette"
```

---

### Task 2: Collapse `AppTheme` to a single dark build, add SnackBar/Dialog/DatePicker/TimePicker theming

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `test/app_theme_test.dart`

**Interfaces:**
- Consumes: `AppColors.*`, `AppPalette.dark` from Task 1.
- Produces: `AppTheme.dark()` — **existing** static method, signature
  unchanged (`static ThemeData dark()`), now the only theme factory.
  `AppTheme.light()` is **deleted** — Task 3 depends on this deletion (its
  own step verifies no caller references it). `AppTheme.boldDialogActions`
  unchanged (reads `Theme.of(context)`, not brightness-specific).

- [ ] **Step 1: Update the failing/changing assertions in `test/app_theme_test.dart`**

Replace the file's contents:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/theme/app_theme.dart';
import 'package:spendly/core/theme/tokens.dart';

void main() {
  group('AppTheme.dialogTheme', () {
    test('title is bold and app text color, content is not bold', () {
      final dialogTheme = AppTheme.dark().dialogTheme;
      expect(dialogTheme.titleTextStyle!.color, AppColors.darkText);
      expect(dialogTheme.titleTextStyle!.fontWeight, FontWeight.w700);
      expect(dialogTheme.contentTextStyle!.color, AppColors.darkText);
      expect(dialogTheme.contentTextStyle!.fontWeight, FontWeight.w400);
    });
  });

  group('AppTheme.boldDialogActions', () {
    testWidgets('bolds TextButton and FilledButton labels', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      final themed = AppTheme.boldDialogActions(capturedContext);
      final textButtonStyle = themed.textButtonTheme.style!.textStyle!
          .resolve({});
      final filledButtonStyle = themed.filledButtonTheme.style!.textStyle!
          .resolve({});

      expect(textButtonStyle!.fontWeight, FontWeight.bold);
      expect(filledButtonStyle!.fontWeight, FontWeight.bold);
    });
  });

  group('AppTheme.dark — SnackBar/DatePicker/TimePicker are themed', () {
    test('snackBarTheme uses card2 surface and gold action color', () {
      final theme = AppTheme.dark();
      expect(theme.snackBarTheme.backgroundColor, AppColors.darkCard2);
      expect(theme.snackBarTheme.actionTextColor, AppColors.primary);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    test('datePickerTheme uses card surfaces', () {
      final theme = AppTheme.dark();
      expect(theme.datePickerTheme.backgroundColor, AppColors.darkCard);
      expect(theme.datePickerTheme.headerBackgroundColor, AppColors.darkCard2);
    });

    test('timePickerTheme uses card surfaces', () {
      final theme = AppTheme.dark();
      expect(theme.timePickerTheme.backgroundColor, AppColors.darkCard);
      expect(theme.timePickerTheme.dialBackgroundColor, AppColors.darkCard2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_theme_test.dart`
Expected: FAIL — `AppTheme.dark()` doesn't set `snackBarTheme`/
`datePickerTheme`/`timePickerTheme` yet, and the dialog test's color
assertion doesn't match (current code still does the `isDark ? text :
Colors.black` ternary against `AppColors.darkText`, so this particular
assertion may already pass — the SnackBar/DatePicker/TimePicker groups are
the ones that must fail here).

- [ ] **Step 3: Replace `lib/core/theme/app_theme.dart`**

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's one ThemeData — Dark Premium. Sora = display/numbers, Inter =
/// body, matching the prototype's font pairing. No light theme exists.
class AppTheme {
  AppTheme._();

  static const _display = 'Sora';
  static const _body = 'Inter';

  static ThemeData dark() => _build();

  /// Wrap an [AlertDialog] with this to bold its action buttons without
  /// affecting buttons elsewhere in the app.
  static ThemeData boldDialogActions(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    final theme = Theme.of(context);
    return theme.copyWith(
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: bold),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(textStyle: bold),
      ),
    );
  }

  static ThemeData _build() {
    const bg = AppColors.darkBg;
    const card = AppColors.darkCard;
    const card2 = AppColors.darkCard2;
    const text = AppColors.darkText;
    const palette = AppPalette.dark;
    // Selected/filled controls (gold day chip, gold time chip) need a dark
    // foreground for contrast — gold is a light-toned accent.
    const onGold = Color(0xFF1A140A);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.pink,
          surface: card,
          error: AppColors.red,
        );

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: _body,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      extensions: const [palette],
      textTheme: _textTheme(text, palette.textDim),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _display,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      dialogTheme: const DialogThemeData(
        titleTextStyle: TextStyle(
          fontFamily: _display,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        contentTextStyle: TextStyle(
          fontFamily: _body,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card2,
        contentTextStyle: const TextStyle(fontFamily: _body, color: text),
        actionTextColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        headerBackgroundColor: card2,
        headerForegroundColor: text,
        weekdayStyle: TextStyle(fontFamily: _body, color: palette.textDim),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onGold : text,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        todayForegroundColor: const WidgetStatePropertyAll(AppColors.primary),
        todayBorder: const BorderSide(color: AppColors.primary),
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
        hourMinuteColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : card2,
        ),
        hourMinuteTextColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onGold : text,
        ),
        dialHandColor: AppColors.primary,
        dialBackgroundColor: card2,
        entryModeIconColor: text,
      ),
    );
  }

  static TextTheme _textTheme(Color text, Color dim) {
    TextStyle display(double size, [FontWeight w = FontWeight.w600]) =>
        TextStyle(
          fontFamily: _display,
          fontSize: size,
          fontWeight: w,
          color: text,
          letterSpacing: -0.5,
        );
    TextStyle body(double size, [FontWeight w = FontWeight.w400, Color? c]) =>
        TextStyle(
          fontFamily: _body,
          fontSize: size,
          fontWeight: w,
          color: c ?? text,
        );

    return TextTheme(
      displayLarge: display(36, FontWeight.w700),
      headlineMedium: display(20),
      titleLarge: display(18),
      titleMedium: display(16),
      bodyLarge: body(15),
      bodyMedium: body(14),
      bodySmall: body(13, FontWeight.w400, dim),
      labelSmall: body(11, FontWeight.w500, dim),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app_theme_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart test/app_theme_test.dart
git commit -m "feat: collapse AppTheme to single dark build with SnackBar/DatePicker/TimePicker theming"
```

---

### Task 3: Wire `MaterialApp` to the single theme, delete theme-mode plumbing

**Files:**
- Modify: `lib/app.dart`
- Delete: `lib/features/settings/theme_mode_provider.dart`
- Modify: `lib/features/profile/delete_all_data_flow.dart`

**Interfaces:**
- Consumes: `AppTheme.dark()` from Task 2.
- Produces: nothing new consumed by later tasks — this is the leaf that
  removes `themeModeProvider` from existence, which Task 4 depends on (it
  removes the last two UI references to that provider).

- [ ] **Step 1: Remove the theme-mode provider file**

```bash
rm lib/features/settings/theme_mode_provider.dart
```

- [ ] **Step 2: Update `lib/app.dart`**

Remove the import (around line 22):

```dart
import 'features/settings/theme_mode_provider.dart';
```

Remove this line from `build()` (around line 137):

```dart
    // Falls back to system while the persisted value loads.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
```

Replace the `MaterialApp(...)` construction (around lines 146-177) — the
`theme`/`darkTheme`/`themeMode` params and the `AnimatedTheme` `builder`
are removed since there is exactly one theme now:

```dart
    return MaterialApp(
      title: 'Spendly',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: (lockEnabled && !unlocked)
          ? const AppLockScreen()
          : profileAsync.when(
              loading: () => const Scaffold(body: LoadingView()),
              error: (e, _) => Scaffold(
                body: ErrorView(
                  message: "Couldn't load your profile.",
                  onRetry: () => ref.invalidate(profileProvider),
                ),
              ),
              data: (profile) => profile.name.isEmpty
                  ? const WelcomeScreen()
                  : const AppShell(),
            ),
    );
```

- [ ] **Step 3: Update `lib/features/profile/delete_all_data_flow.dart`**

Remove the import (around line 8):

```dart
import '../settings/theme_mode_provider.dart';
```

Remove this line from `runDeleteAllDataFlow` (around line 36):

```dart
  ref.invalidate(themeModeProvider);
```

So the surrounding block reads:

```dart
  await ref.read(databaseProvider).resetToDefaults();
  ref.invalidate(profileProvider);
```

- [ ] **Step 4: Confirm no remaining references**

Run: `grep -rn "themeModeProvider\|theme_mode_provider\|ThemeModeNotifier" lib/ test/`
Expected: no output.

- [ ] **Step 5: Run static analysis**

Run: `flutter analyze`
Expected: no errors. (`profile_screen.dart` will still reference
`themeModeProvider` at this point — Task 4 fixes that. If analyze is run
strictly per-task, expect errors there until Task 4 lands; running it here
is a checkpoint on `app.dart`/`delete_all_data_flow.dart` specifically —
grep for those two files' errors if the full-project run is noisy:)

Run: `flutter analyze lib/app.dart lib/features/profile/delete_all_data_flow.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/app.dart lib/features/profile/delete_all_data_flow.dart
git rm lib/features/settings/theme_mode_provider.dart
git commit -m "feat: wire MaterialApp to the single Dark Premium theme, drop theme-mode plumbing"
```

---

### Task 4: Remove the Theme setting from Profile, drop the dead settings key

**Files:**
- Modify: `lib/features/profile/profile_screen.dart`
- Modify: `lib/core/db/providers.dart`

**Interfaces:**
- Consumes: nothing new (this task only deletes code).
- Produces: nothing consumed elsewhere — end of Phase 1's chain.

- [ ] **Step 1: Update `lib/features/profile/profile_screen.dart`**

Remove the import (around line 10):

```dart
import '../settings/theme_mode_provider.dart';
```

Remove this line from `build()` (around line 36):

```dart
    final themeModeAsync = ref.watch(themeModeProvider);
```

Remove the Theme `_MenuRow` from the `'General'` section (around lines
140-151), leaving only Currency:

```dart
            const SectionTitle('General'),
            _MenuGroup(
              children: [
                const _MenuRow(
                  icon: Icons.currency_rupee,
                  title: 'Currency',
                  subtitle: 'Indian Rupee (₹)',
                  onTap: null, // read-only: multi-currency is v2, PROGRESS.md
                ),
              ],
            ),
```

Remove the `_themeLabel` and `_openThemePicker` methods entirely (around
lines 260-309 — everything from `String _themeLabel(ThemeMode m) => ...`
through the closing `}` of `_openThemePicker`, right before the
`_EditBadge` class).

- [ ] **Step 2: Update `lib/core/db/providers.dart`**

Remove the now-dead settings key (around line 18):

```dart
  static const themeModeKey = 'theme_mode';
```

- [ ] **Step 3: Confirm no remaining references**

Run: `grep -rn "themeModeProvider\|themeModeKey\|_themeLabel\|_openThemePicker\|ThemeMode\." lib/ test/`
Expected: no output. (If `ThemeMode.` still appears anywhere, it's a
leftover this task must also remove — the whole concept is gone from the
app.)

- [ ] **Step 4: Run static analysis and the full test suite**

Run: `flutter analyze`
Expected: no errors, no warnings about unused imports.

Run: `flutter test`
Expected: all tests pass, including `test/tokens_test.dart` and
`test/app_theme_test.dart` from Tasks 1-2.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/profile_screen.dart lib/core/db/providers.dart
git commit -m "feat: remove Theme setting from Profile, app is Dark Premium only"
```

---

## Phase 1 exit check

Before moving to Phase 2 (shared components) or any screen-restyle phase:

- [ ] `flutter analyze` clean on the whole project.
- [ ] `flutter test` green on the whole project.
- [ ] `grep -rn "ThemeMode\|themeMode" lib/` returns nothing (the concept is
      fully gone, not just unreachable).
- [ ] Manually launch the app (`flutter run`) and confirm it renders in the
      new gold/violet/near-black palette with no light-mode flash on cold
      start — **note:** per this session's standing instruction, the user
      runs the app themselves; report readiness for that check rather than
      running it here.

## What comes after this plan

Per the spec's rollout order, Phases 2-7 (shared components; the 8
mockup'd screens; chart-screen recolor; Monthly Recap; the remaining ~16
screens; the native iOS/Android home-screen widget) are each written as
their **own** plan document once the phase before them has landed — mainly
because Phase 2 onward involves adding real glass/blur rendering to
`AppCard` and friends, a design decision worth making against the actual
running dark app rather than guessed in advance, and because writing
correct, placeholder-free code for ~30 screens requires reading each of
those files in full first, which this plan intentionally scoped out to keep
Phase 1 reviewable on its own.

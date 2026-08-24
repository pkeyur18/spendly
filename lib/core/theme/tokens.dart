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

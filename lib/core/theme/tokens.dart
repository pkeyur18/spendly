import 'package:flutter/material.dart';

/// Design tokens translated verbatim from spendly-prototype.html `:root`.
/// Single source of truth for color, spacing, radius, type. Do not hardcode
/// hex/sizes in widgets — reference these.
class AppColors {
  AppColors._();

  // Brand (theme-independent)
  static const primary = Color(0xFF6366F1);
  static const primarySoft = Color(0xFF818CF8);
  static const primaryDeep = Color(0xFF4F46E5);
  static const accent = Color(0xFFF59E0B);
  static const pink = Color(0xFFEC4899);
  static const teal = Color(0xFF14B8A6);
  static const red = Color(0xFFEF4444);

  // Light
  static const lightBg = Color(0xFFF5F5F7);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCard2 = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF14141C);
  static const lightTextDim = Color(0xFF6B6B7B);
  static const lightLine = Color(0xFFECECF1);

  // Dark
  static const darkBg = Color(0xFF0B0B12);
  static const darkCard = Color(0xFF16161F);
  static const darkCard2 = Color(0xFF1D1D28);
  static const darkText = Color(0xFFF4F4F8);
  static const darkTextDim = Color(0xFF8B8B9C);
  static const darkLine = Color(0xFF26262F);

  // Bottom nav (own indigo-plum surface, distinct from card)
  static const navBgLight = Color(0xFF1B1533);
  static const navBgDark = Color(0xFF201A3D);
  static const navIconOffLight = Color(0xFF8B84B0);
  static const navIconOffDark = Color(0xFF9086B8);

  /// Hero / FAB / primary-button gradient (135deg deep → primary → pink).
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

  static const light = AppPalette(
    card: AppColors.lightCard,
    card2: AppColors.lightCard2,
    textDim: AppColors.lightTextDim,
    line: AppColors.lightLine,
    navBackground: AppColors.navBgLight,
    navIconInactive: AppColors.navIconOffLight,
    navBorder: Color(0x0FFFFFFF),
  );

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
  static const card = 22.0;
  static const hero = 26.0;
  static const button = 16.0;
  static const icon = 13.0;
}

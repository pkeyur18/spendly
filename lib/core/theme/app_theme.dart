import 'package:flutter/material.dart';

import 'tokens.dart';

/// Light + dark ThemeData built from [AppColors]. Sora = display/numbers,
/// Inter = body, matching the prototype's font pairing.
class AppTheme {
  AppTheme._();

  static const _display = 'Sora';
  static const _body = 'Inter';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final text = isDark ? AppColors.darkText : AppColors.lightText;
    final palette = isDark ? AppPalette.dark : AppPalette.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.pink,
      surface: card,
      error: AppColors.red,
    );

    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: _body,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      extensions: [palette],
      textTheme: _textTheme(text, palette.textDim),
      appBarTheme: AppBarTheme(
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
    );
  }

  static TextTheme _textTheme(Color text, Color dim) {
    TextStyle display(double size, [FontWeight w = FontWeight.w600]) =>
        TextStyle(fontFamily: _display, fontSize: size, fontWeight: w, color: text, letterSpacing: -0.5);
    TextStyle body(double size, [FontWeight w = FontWeight.w400, Color? c]) =>
        TextStyle(fontFamily: _body, fontSize: size, fontWeight: w, color: c ?? text);

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

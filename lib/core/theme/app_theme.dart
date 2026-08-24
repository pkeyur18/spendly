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
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : card2,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
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

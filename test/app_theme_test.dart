import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/theme/app_theme.dart';
import 'package:spendly/core/theme/tokens.dart';

void main() {
  group('AppTheme.dialogTheme', () {
    test('light mode: title is black and bold, content is black but not bold', () {
      final dialogTheme = AppTheme.light().dialogTheme;
      expect(dialogTheme.titleTextStyle!.color, Colors.black);
      expect(dialogTheme.titleTextStyle!.fontWeight, FontWeight.w700);
      expect(dialogTheme.contentTextStyle!.color, Colors.black);
      expect(dialogTheme.contentTextStyle!.fontWeight, FontWeight.w400);
    });

    test('dark mode: text stays app text color, title bold, content not', () {
      final dialogTheme = AppTheme.dark().dialogTheme;
      expect(dialogTheme.titleTextStyle!.color, isNot(Colors.black));
      expect(dialogTheme.titleTextStyle!.fontWeight, FontWeight.w700);
      expect(dialogTheme.contentTextStyle!.fontWeight, FontWeight.w400);
    });
  });

  group('AppTheme.boldDialogActions', () {
    testWidgets('bolds TextButton and FilledButton labels', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
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

  group('AppTheme — SnackBar/DatePicker/TimePicker themed in both modes', () {
    test('light: uses light card surfaces and the brand accent', () {
      final theme = AppTheme.light();
      expect(theme.snackBarTheme.backgroundColor, AppColors.lightCard2);
      expect(theme.snackBarTheme.actionTextColor, AppColors.primary);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.datePickerTheme.backgroundColor, AppColors.lightCard);
      expect(theme.datePickerTheme.headerBackgroundColor, AppColors.lightCard2);
      expect(theme.timePickerTheme.backgroundColor, AppColors.lightCard);
      expect(theme.timePickerTheme.dialBackgroundColor, AppColors.lightCard2);
    });

    test('dark: uses dark card surfaces and the brand accent', () {
      final theme = AppTheme.dark();
      expect(theme.snackBarTheme.backgroundColor, AppColors.darkCard2);
      expect(theme.snackBarTheme.actionTextColor, AppColors.primary);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.datePickerTheme.backgroundColor, AppColors.darkCard);
      expect(theme.datePickerTheme.headerBackgroundColor, AppColors.darkCard2);
      expect(theme.timePickerTheme.backgroundColor, AppColors.darkCard);
      expect(theme.timePickerTheme.dialBackgroundColor, AppColors.darkCard2);
    });
  });
}

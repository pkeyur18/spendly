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

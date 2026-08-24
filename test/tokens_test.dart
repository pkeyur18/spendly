import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/theme/tokens.dart';

void main() {
  group('AppPalette — glass surface tokens', () {
    test('light theme glass card/border are distinct from the flat card', () {
      expect(AppPalette.light.glassCard, const Color(0xE6FFFFFF));
      expect(AppPalette.light.glassBorder, const Color(0x14000000));
      expect(AppPalette.light.glassCard, isNot(AppPalette.light.card));
    });

    test('dark theme glass card/border are distinct from the flat card', () {
      expect(AppPalette.dark.glassCard, const Color(0x1FFFFFFF));
      expect(AppPalette.dark.glassBorder, const Color(0x21FFFFFF));
      expect(AppPalette.dark.glassCard, isNot(AppPalette.dark.card));
    });

    test('lerp interpolates the new fields too', () {
      final mid = AppPalette.light.lerp(AppPalette.dark, 1.0);
      expect(mid.glassCard, AppPalette.dark.glassCard);
      expect(mid.glassBorder, AppPalette.dark.glassBorder);
    });

    test('copyWith overrides only the new fields when asked', () {
      const override = Color(0xFF00FF00);
      final copy = AppPalette.light.copyWith(glassCard: override);
      expect(copy.glassCard, override);
      expect(copy.glassBorder, AppPalette.light.glassBorder);
      expect(copy.card, AppPalette.light.card);
    });
  });

  group('AppRadius.glassBlurSigma', () {
    test('is a positive blur amount shared by both themes', () {
      expect(AppRadius.glassBlurSigma, 20.0);
    });
  });
}

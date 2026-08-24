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

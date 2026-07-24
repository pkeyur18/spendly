import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/profile/avatar.dart';

void main() {
  group('initialsFor', () {
    test('single word takes its first grapheme', () {
      expect(initialsFor('Ada'), 'A');
    });

    test('multi-word name takes first + last word initials', () {
      expect(initialsFor('Aditi Sharma'), 'AS');
      expect(initialsFor('  Mary   Jane   Watson  '), 'MW');
    });

    test('blank/whitespace-only name resolves to empty, never throws', () {
      expect(initialsFor(''), '');
      expect(initialsFor('   '), '');
    });

    test('emoji/special-character name never throws and is non-empty', () {
      expect(() => initialsFor('🐶 Rex'), returnsNormally);
      expect(initialsFor('🐶 Rex').isNotEmpty, isTrue);
      expect(() => initialsFor('🐶🐱'), returnsNormally);
      expect(initialsFor('🐶🐱').isNotEmpty, isTrue);
    });
  });

  group('gradientAt', () {
    test('index 0 is the default gradient', () {
      expect(gradientAt(null).colors, gradientAt(0).colors);
    });

    test('every avatarGradients index resolves to a renderable gradient', () {
      for (var i = 0; i < avatarGradients.length; i++) {
        expect(gradientAt(i).colors, isNotEmpty);
      }
    });

    test('out-of-range index clamps instead of throwing', () {
      expect(() => gradientAt(999), returnsNormally);
      expect(() => gradientAt(-5), returnsNormally);
    });
  });
}

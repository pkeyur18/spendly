import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/fx.dart';
import 'package:spendly/core/money/money.dart';

void main() {
  group('convertToHomeMinor', () {
    test('converts at the trip rate', () {
      // ฿450.00 at 2.62 INR/THB = ₹1,179.00
      expect(convertToHomeMinor(45000, 2620000), 117900);
      // ฿250.00 -> ₹655.00
      expect(convertToHomeMinor(25000, 2620000), 65500);
    });

    test('rounds half-up on the sub-paise remainder', () {
      // 1 minor unit at rate 0.5 = 0.5 exactly -> rounds up to 1.
      expect(convertToHomeMinor(1, rateScale ~/ 2), 1);
      // 0.4 rounds down.
      expect(convertToHomeMinor(1, 400000), 0);
      // 0.6 rounds up.
      expect(convertToHomeMinor(1, 600000), 1);
    });

    test('is exact for a rate of 1', () {
      expect(convertToHomeMinor(123456, rateScale), 123456);
    });

    test('handles zero', () {
      expect(convertToHomeMinor(0, 2620000), 0);
      expect(convertToHomeMinor(45000, 0), 0);
    });

    test('rounds negatives away from zero, symmetrically', () {
      expect(convertToHomeMinor(-1, 600000), -1);
      expect(convertToHomeMinor(-45000, 2620000), -117900);
    });

    test('stays exact on a large trip total', () {
      // ₹1 crore worth of yen at 0.55 INR/JPY — well inside 64-bit int.
      final home = convertToHomeMinor(1818181818, 550000);
      expect(home, 1000000000);
    });
  });

  group('parseRateMicros', () {
    test('parses decimals without going through double', () {
      expect(parseRateMicros('2.62'), 2620000);
      expect(parseRateMicros('2'), 2000000);
      expect(parseRateMicros('0.000001'), 1);
      expect(parseRateMicros('.5'), 500000);
    });

    test('tolerates whitespace and thousands separators', () {
      expect(parseRateMicros('  2.62 '), 2620000);
      expect(parseRateMicros('1,234.5'), 1234500000);
    });

    test('truncates precision beyond six decimals', () {
      expect(parseRateMicros('2.1234567'), 2123456);
    });

    test('rejects anything that is not a positive number', () {
      expect(parseRateMicros(''), isNull);
      expect(parseRateMicros('   '), isNull);
      expect(parseRateMicros('abc'), isNull);
      expect(parseRateMicros('2.6.2'), isNull);
      expect(parseRateMicros('-2.62'), isNull);
      expect(parseRateMicros('0'), isNull);
      expect(parseRateMicros('0.0'), isNull);
      expect(parseRateMicros('2,'), 2000000); // trailing separator is stripped
    });
  });

  group('rateToString', () {
    test('round-trips through parseRateMicros', () {
      for (final s in ['2.62', '1', '0.5', '83.125', '0.000001']) {
        expect(rateToString(parseRateMicros(s)!), s);
      }
    });

    test('drops trailing zeros and a bare decimal point', () {
      expect(rateToString(2620000), '2.62');
      expect(rateToString(2000000), '2');
      expect(rateToString(2600000), '2.6');
    });
  });

  group('averageRateMicros', () {
    test('derives the blended rate from stored totals', () {
      // ₹1,179.00 home for ฿450.00 foreign = 2.62
      expect(averageRateMicros(117900, 45000), 2620000);
    });

    test('blends two different rates honestly', () {
      // ฿450 at 2.62 (₹1179) then ฿450 at 2.90 (₹1305) = ₹2484 / ฿900
      final avg = averageRateMicros(248400, 90000);
      expect(avg, 2760000); // 2.76, the midpoint
    });

    test('is null when nothing foreign was spent', () {
      expect(averageRateMicros(117900, 0), isNull);
    });
  });

  group('Money.formatAs', () {
    test('uses the foreign currency symbol', () {
      expect(Money.fromMinor(45000).formatAs('THB'), contains('450'));
    });

    test('drops decimals for a zero-decimal currency', () {
      // ¥1500 stored as two-decimal minor units still renders without digits.
      final yen = Money.fromMinor(150000).formatAs('JPY');
      expect(yen, contains('1,500'));
      expect(yen, isNot(contains('1,500.00')));
    });
  });
}

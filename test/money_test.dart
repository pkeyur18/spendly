import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/money.dart';

void main() {
  group('Money — exact minor-unit arithmetic', () {
    test('parse major string to minor units', () {
      expect(Money.parse('24.50').minor, 2450);
      expect(Money.parse('1240').minor, 124000);
      expect(Money.parse('0').minor, 0);
      expect(Money.parse('1,240.99').minor, 124099); // strips grouping
    });

    test('the classic float trap stays exact', () {
      // 0.10 + 0.20 == 0.30 exactly with minor units (would be 0.30000...4 as double)
      final sum = Money.parse('0.10') + Money.parse('0.20');
      expect(sum.minor, 30);
      expect(sum, Money.fromMinor(30));
    });

    test('add / subtract / multiply', () {
      expect((Money.fromMinor(35000) + Money.fromMinor(124000)).minor, 159000);
      expect((Money.fromMinor(159000) - Money.fromMinor(35000)).minor, 124000);
      expect((Money.fromMinor(350) * 3).minor, 1050);
    });

    test('rounds half away from zero at 2 decimals', () {
      expect(Money.parse('1.005').minor, 101); // .round() on 100.5 -> 101
      expect(Money.parse('1.994').minor, 199);
    });

    test('ratioOf budget for the budget bar', () {
      final spent = Money.fromMinor(2435000); // 24,350
      final budget = Money.fromMinor(4000000); // 40,000
      expect((spent.ratioOf(budget) * 100).round(), 61); // prototype's 61%
      expect(spent.ratioOf(Money.zero), 0); // no divide-by-zero
    });

    test('comparisons', () {
      expect(Money.fromMinor(100) < Money.fromMinor(200), isTrue);
      expect(Money.fromMinor(200) >= Money.fromMinor(200), isTrue);
    });
  });

  group('Money — formatting round-trips', () {
    test('en_IN grouping and symbol', () {
      final f = Money.fromMinor(2435000).format(locale: 'en_IN');
      expect(f, contains('₹'));
      expect(f, contains('24,350'));
    });

    test('compact form', () {
      final f = Money.fromMinor(2435000).formatCompact(locale: 'en_IN');
      expect(f, contains('24'));
    });

    test('format value equals major units', () {
      expect(Money.fromMinor(2450).major, 24.50);
    });
  });
}

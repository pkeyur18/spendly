import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/recap/recap_summary.dart';

void main() {
  Money m(String s) => Money.parse(s);

  group('no budget set', () {
    test('null budget -> hasBudget false, savings/percentUsed null', () {
      final s = computeRecapSummary(total: m('500'), budget: null);
      expect(s.hasBudget, isFalse);
      expect(s.isPositive, isFalse);
      expect(s.savings, isNull);
      expect(s.percentUsed, isNull);
    });

    test('zero-amount budget treated same as no budget (matches _HeroCard gate)', () {
      final s = computeRecapSummary(total: m('500'), budget: Money.zero);
      expect(s.hasBudget, isFalse);
      expect(s.savings, isNull);
    });
  });

  group('spend under budget', () {
    test('positive savings, correct amount and percent', () {
      final s = computeRecapSummary(total: m('24350'), budget: m('40000'));
      expect(s.hasBudget, isTrue);
      expect(s.isPositive, isTrue);
      expect(s.savings, m('15650'));
      expect(s.percentUsed, 61); // 24350/40000 = 60.875% -> rounds to 61
    });
  });

  group('spend over budget', () {
    test('negative savings by the overrun amount, not positive', () {
      final s = computeRecapSummary(total: m('43200'), budget: m('40000'));
      expect(s.hasBudget, isTrue);
      expect(s.isPositive, isFalse);
      expect(s.savings, m('-3200'));
      expect(s.percentUsed, 108);
    });
  });

  group('break-even', () {
    test('spend exactly equal to budget counts as positive', () {
      final s = computeRecapSummary(total: m('40000'), budget: m('40000'));
      expect(s.isPositive, isTrue);
      expect(s.savings, Money.zero);
      expect(s.percentUsed, 100);
    });
  });
}

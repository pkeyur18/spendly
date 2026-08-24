import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/ledger/cashflow_math.dart';

void main() {
  group('computeCashflow', () {
    test('net is income minus expense', () {
      final s = computeCashflow(
        income: Money.parse('50000'),
        expense: Money.parse('39000'),
      );
      expect(s.net, Money.parse('11000'));
    });

    test('savings rate rounds to the nearest percent', () {
      final s = computeCashflow(
        income: Money.parse('50000'),
        expense: Money.parse('39000'),
      );
      expect(s.savingsRatePercent, 22); // 11000/50000 = 22%
    });

    test('savings rate is null when income is zero — nothing to divide by', () {
      final s = computeCashflow(income: Money.zero, expense: Money.parse('500'));
      expect(s.savingsRatePercent, isNull);
      expect(s.net, Money.parse('-500'));
    });

    test('spending more than income gives a negative rate, not null', () {
      final s = computeCashflow(
        income: Money.parse('1000'),
        expense: Money.parse('1500'),
      );
      expect(s.savingsRatePercent, -50);
      expect(s.net, Money.parse('-500'));
    });

    test('all income kept, zero expense', () {
      final s = computeCashflow(income: Money.parse('1000'), expense: Money.zero);
      expect(s.savingsRatePercent, 100);
      expect(s.net, Money.parse('1000'));
    });
  });
}

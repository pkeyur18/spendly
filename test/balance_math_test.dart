import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/ledger/balance_math.dart';

void main() {
  group('computeAccountBalance', () {
    test('opening plus income minus expense, no transfers', () {
      final b = computeAccountBalance(
        openingBalance: Money.parse('1000'),
        income: Money.parse('5000'),
        expense: Money.parse('2000'),
        transfersIn: Money.zero,
        transfersOut: Money.zero,
      );
      expect(b, Money.parse('4000'));
    });

    test('a transfer in adds, a transfer out subtracts', () {
      final b = computeAccountBalance(
        openingBalance: Money.zero,
        income: Money.zero,
        expense: Money.zero,
        transfersIn: Money.parse('300'),
        transfersOut: Money.parse('100'),
      );
      expect(b, Money.parse('200'));
    });

    test('everything at zero is zero', () {
      final b = computeAccountBalance(
        openingBalance: Money.zero,
        income: Money.zero,
        expense: Money.zero,
        transfersIn: Money.zero,
        transfersOut: Money.zero,
      );
      expect(b, Money.zero);
    });

    test('can go negative — spent and transferred out more than was there',
        () {
      final b = computeAccountBalance(
        openingBalance: Money.parse('100'),
        income: Money.zero,
        expense: Money.parse('300'),
        transfersIn: Money.zero,
        transfersOut: Money.parse('50'),
      );
      expect(b, Money.parse('-250'));
    });

    test('all five terms combine correctly', () {
      final b = computeAccountBalance(
        openingBalance: Money.parse('1000'),
        income: Money.parse('500'),
        expense: Money.parse('300'),
        transfersIn: Money.parse('200'),
        transfersOut: Money.parse('150'),
      );
      // 1000 + 500 - 300 + 200 - 150 = 1250
      expect(b, Money.parse('1250'));
    });
  });
}

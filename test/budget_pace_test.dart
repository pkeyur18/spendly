import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_pace.dart';

void main() {
  BudgetPace? pace(String spent, String? budget, DateTime now) => budgetPace(
    spent: Money.parse(spent),
    budget: budget == null ? null : Money.parse(budget),
    now: now,
  );

  group('no pace to show', () {
    test('null budget', () {
      expect(pace('500', null, DateTime(2026, 6, 15)), isNull);
    });

    test('zero budget behaves like no budget', () {
      // Matches _HeroCard's existing `budget.minor > 0` gate — a ₹0 budget is
      // not a budget, and dividing by it would be meaningless anyway.
      expect(pace('500', '0', DateTime(2026, 6, 15)), isNull);
    });
  });

  group('days-left arithmetic', () {
    test('first day of a 30-day month leaves all 30 days', () {
      final p = pace('0', '30000', DateTime(2026, 6, 1))!;
      expect(p.daysLeft, 30);
      // Whole budget spread over the whole month.
      expect(p.perDayLeft, Money.parse('1000'));
    });

    test('last day of the month leaves exactly one day', () {
      final p = pace('29000', '30000', DateTime(2026, 6, 30))!;
      expect(p.daysLeft, 1);
      expect(p.perDayLeft, Money.parse('1000'));
    });

    test('31-day month counts 31, not 30', () {
      expect(pace('0', '31000', DateTime(2026, 7, 1))!.daysLeft, 31);
    });

    test('February in a leap year counts 29', () {
      expect(pace('0', '29000', DateTime(2028, 2, 1))!.daysLeft, 29);
    });

    test('February in a non-leap year counts 28', () {
      expect(pace('0', '28000', DateTime(2026, 2, 1))!.daysLeft, 28);
    });
  });

  group('status', () {
    // June 2026: 30 days. On day 15, half the month is gone, so half the
    // budget is the expected spend.
    final midJune = DateTime(2026, 6, 15);

    test('under the expected pace is on track', () {
      final p = pace('10000', '30000', midJune)!;
      expect(p.expectedByNow, Money.parse('15000'));
      expect(p.status, PaceStatus.onTrack);
    });

    test('exactly on the expected pace is still on track', () {
      expect(pace('15000', '30000', midJune)!.status, PaceStatus.onTrack);
    });

    test('past the expected pace but under budget is overPace', () {
      expect(pace('20000', '30000', midJune)!.status, PaceStatus.overPace);
    });

    test('spending the whole budget is overBudget', () {
      expect(pace('30000', '30000', midJune)!.status, PaceStatus.overBudget);
    });

    test('past the budget is overBudget', () {
      expect(pace('45000', '30000', midJune)!.status, PaceStatus.overBudget);
    });
  });

  group('per-day allowance', () {
    test('splits what is left across the days that are left', () {
      // Day 15 of 30 → 16 days left (today included). ₹8,000 left / 16.
      final p = pace('22000', '30000', DateTime(2026, 6, 15))!;
      expect(p.daysLeft, 16);
      expect(p.perDayLeft, Money.parse('500'));
    });

    test('never goes negative once the budget is blown', () {
      final p = pace('45000', '30000', DateTime(2026, 6, 15))!;
      expect(p.perDayLeft, Money.zero);
      expect(p.overspend, Money.parse('15000'));
    });

    test('overspend is zero while still inside the budget', () {
      expect(pace('10000', '30000', DateTime(2026, 6, 15))!.overspend,
          Money.zero);
    });

    test('truncates rather than rounding up, so the total never overshoots',
        () {
      // ₹100 left over 3 days = ₹33.33... → ₹33.33, not ₹33.34.
      final p = pace('29900', '30000', DateTime(2026, 6, 28))!;
      expect(p.daysLeft, 3);
      expect(p.perDayLeft, Money.parse('33.33'));
    });
  });

  test('time of day does not affect the day count', () {
    final morning = pace('0', '30000', DateTime(2026, 6, 15, 6))!;
    final night = pace('0', '30000', DateTime(2026, 6, 15, 23, 59))!;
    expect(morning.daysLeft, night.daysLeft);
    expect(morning.perDayLeft, night.perDayLeft);
  });
}

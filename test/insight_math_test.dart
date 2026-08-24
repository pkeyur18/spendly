import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/insights/insight_math.dart';

void main() {
  group('CategoryTrend.percentChange', () {
    test('up 50% rounds correctly', () {
      final t = CategoryTrend(
        categoryName: 'Food',
        current: Money.parse('1500'),
        priorAverage: Money.parse('1000'),
      );
      expect(t.percentChange, 50);
    });

    test('down 40%', () {
      final t = CategoryTrend(
        categoryName: 'Food',
        current: Money.parse('600'),
        priorAverage: Money.parse('1000'),
      );
      expect(t.percentChange, -40);
    });

    test('null when there is no prior average — nothing to compare against',
        () {
      final t = CategoryTrend(
        categoryName: 'New category',
        current: Money.parse('500'),
        priorAverage: Money.zero,
      );
      expect(t.percentChange, isNull);
    });
  });

  group('significantCategoryTrends', () {
    test('flags a category that moved past the threshold', () {
      final trends = [
        CategoryTrend(
          categoryName: 'Food',
          current: Money.parse('1500'),
          priorAverage: Money.parse('1000'),
        ),
      ];
      final flagged = significantCategoryTrends(trends, thresholdPercent: 30);
      expect(flagged, hasLength(1));
      expect(flagged.single.categoryName, 'Food');
    });

    test('excludes a category that moved less than the threshold', () {
      final trends = [
        CategoryTrend(
          categoryName: 'Food',
          current: Money.parse('1100'),
          priorAverage: Money.parse('1000'),
        ),
      ];
      expect(significantCategoryTrends(trends, thresholdPercent: 30), isEmpty);
    });

    test('excludes a category below the minimum absolute amount even with a '
        'huge percent swing', () {
      final trends = [
        CategoryTrend(
          categoryName: 'Misc',
          current: Money.parse('20'),
          priorAverage: Money.parse('5'),
        ),
      ];
      final flagged = significantCategoryTrends(
        trends,
        thresholdPercent: 30,
        minCurrentMinor: Money.parse('500').minor,
      );
      expect(flagged, isEmpty);
    });

    test('excludes a category with no prior average (null percentChange)',
        () {
      final trends = [
        CategoryTrend(
          categoryName: 'New',
          current: Money.parse('1000'),
          priorAverage: Money.zero,
        ),
      ];
      expect(significantCategoryTrends(trends), isEmpty);
    });

    test('sorts by the size of the move, largest first', () {
      final trends = [
        CategoryTrend(
          categoryName: 'Small move',
          current: Money.parse('1300'),
          priorAverage: Money.parse('1000'),
        ),
        CategoryTrend(
          categoryName: 'Big move',
          current: Money.parse('3000'),
          priorAverage: Money.parse('1000'),
        ),
      ];
      final flagged = significantCategoryTrends(trends, thresholdPercent: 30);
      expect(flagged.map((t) => t.categoryName), ['Big move', 'Small move']);
    });
  });

  group('monthlySubscriptionsTotal', () {
    test('a monthly recurring expense counts at face value', () async {
      // Built via the pure math only — no DB round-trip needed for these
      // amounts/recurrence combinations.
      final total = monthlySubscriptionsTotal([
        _template(amountMinor: 50000, recurrence: Recurrence.monthly),
      ]);
      expect(total, Money.parse('500'));
    });

    test('a weekly recurring expense is normalized to its monthly equivalent',
        () {
      // 100 * (365/12/7) ≈ 434.52 minor units per month for a ₹1/week charge.
      final total = monthlySubscriptionsTotal([
        _template(amountMinor: 100, recurrence: Recurrence.weekly),
      ]);
      expect(total.minor, 435); // rounds to the nearest paisa
    });

    test('a daily recurring expense is normalized to its monthly equivalent',
        () {
      // 100 * (365/12) ≈ 3041.67 minor units per month for a ₹1/day charge.
      final total = monthlySubscriptionsTotal([
        _template(amountMinor: 100, recurrence: Recurrence.daily),
      ]);
      expect(total.minor, 3042);
    });

    test('sums across multiple templates', () {
      final total = monthlySubscriptionsTotal([
        _template(amountMinor: 20000, recurrence: Recurrence.monthly),
        _template(amountMinor: 10000, recurrence: Recurrence.monthly),
      ]);
      expect(total, Money.parse('300'));
    });

    test('empty list totals to zero', () {
      expect(monthlySubscriptionsTotal([]), Money.zero);
    });
  });
}

ExpenseRow _template({required int amountMinor, required Recurrence recurrence}) {
  final now = DateTime.now();
  return ExpenseRow(
    id: 1,
    amountMinor: amountMinor,
    categoryId: 1,
    date: now,
    paymentMethod: null,
    isRecurring: true,
    recurrence: recurrence,
    createdAt: now,
    updatedAt: now,
  );
}

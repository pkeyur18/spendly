import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_recommendation.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/tags/tag_repository.dart';

void main() {
  group('recommendCategoryBudget', () {
    test('null when every month is zero', () {
      expect(recommendCategoryBudget(List.filled(6, Money.zero)), isNull);
    });

    test('flat history rounds to itself at a ₹50 boundary', () {
      final totals = List.filled(6, Money.fromMinor(300000)); // ₹3000 x6
      expect(recommendCategoryBudget(totals), Money.fromMinor(300000));
    });

    test('weights recent months higher than older ones', () {
      // Oldest -> newest: 1000 x5, then 1500 — kept under the 1.75x outlier
      // threshold on purpose, so only weighting is under test here.
      final totals = [
        for (var i = 0; i < 5; i++) Money.fromMinor(100000),
        Money.fromMinor(150000),
      ];
      final plainAverage =
          totals.fold(0, (a, m) => a + m.minor) ~/ totals.length;
      final result = recommendCategoryBudget(totals)!;
      // Weighting the newest (heaviest-weighted) month higher pulls the
      // result above the plain average.
      expect(result.minor, greaterThan(plainAverage));
    });

    test('drops a single month exceeding 1.75x the median (>=4 months only)', () {
      // Median of the five 1000s is 1000; 5000 > 1.75x1000, so it's dropped.
      final totals = [
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(500000),
      ];
      final result = recommendCategoryBudget(totals)!;
      // With the outlier dropped, every remaining month is ₹1000 flat.
      expect(result, Money.fromMinor(100000));
    });

    test('outlier guard is skipped with fewer than 4 months of data', () {
      // A caller trims the fixed 6-slot window down to just the months that
      // are real history (see monthsUsedInWindow) before calling this
      // function — so it must also behave correctly on short lists.
      final totals = [
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(500000), // would be dropped at >=4 months; kept here
      ];
      final result = recommendCategoryBudget(totals)!;
      // Weights 1,2,3, nothing dropped: (100000*1 + 100000*2 + 500000*3) / 6
      // = 300000 exactly, already on a ₹50 boundary.
      expect(result, Money.fromMinor(300000));
    });
  });

  group('monthsUsedInWindow', () {
    final now = DateTime(2026, 8, 15);

    test('null earliest date -> 0 months used', () {
      expect(monthsUsedInWindow(null, now), 0);
    });

    test('earliest expense 3 months ago -> 3 months used', () {
      expect(monthsUsedInWindow(DateTime(2026, 5, 20), now), 3);
    });

    test('earliest expense before the whole window -> full 6 months used', () {
      expect(monthsUsedInWindow(DateTime(2024, 1, 1), now), 6);
    });
  });

  group('monthlyCategoryTotals', () {
    late AppDatabase db;
    late ExpenseRepository expenses;
    late TagRepository tags;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      expenses = ExpenseRepository(db);
      tags = TagRepository(db);
    });
    tearDown(() => db.close());

    test('buckets by month and category, oldest to newest', () async {
      final now = DateTime(2026, 8, 15);
      await expenses.add(
        amount: Money.parse('1000'),
        categoryId: 1,
        date: DateTime(2026, 7, 10), // 1 month back -> last bucket
      );
      await expenses.add(
        amount: Money.parse('2000'),
        categoryId: 1,
        date: DateTime(2026, 2, 10), // 6 months back -> first bucket
      );
      final rows = await expenses
          .watchInRange(DateTime(2026, 2, 1), DateTime(2026, 8, 1))
          .first;

      final buckets = monthlyCategoryTotals(rows, {}, now);
      expect(buckets.length, 6);
      expect(buckets.first[1], Money.parse('2000')); // Feb, oldest
      expect(buckets.last[1], Money.parse('1000')); // Jul, newest
    });

    test('excludes trip-tagged expenses', () async {
      final now = DateTime(2026, 8, 15);
      final tripTagId = await tags.create(
        name: 'Bali',
        colorValue: 0xFF000000,
        tripStartDate: DateTime(2026, 7, 1),
        tripEndDate: DateTime(2026, 7, 5),
      );
      await expenses.add(
        amount: Money.parse('5000'),
        categoryId: 1,
        date: DateTime(2026, 7, 2),
        tagId: tripTagId,
      );
      await expenses.add(
        amount: Money.parse('500'),
        categoryId: 1,
        date: DateTime(2026, 7, 3),
      );
      final rows = await expenses
          .watchInRange(DateTime(2026, 2, 1), DateTime(2026, 8, 1))
          .first;

      final buckets = monthlyCategoryTotals(rows, {tripTagId}, now);
      expect(buckets.last[1], Money.parse('500')); // trip expense excluded
    });
  });
}

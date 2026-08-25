import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/reports/past_month_picker_sheet.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository expenses;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenses = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  test(
    'bucketPastMonths: 12 buckets, newest first, excludes current month',
    () async {
      final now = DateTime(2026, 6, 15);
      final currentMonth = DateTime(2026, 6, 10);
      final lastMonth = DateTime(2026, 5, 20);
      final twelveMonthsAgo = DateTime(2025, 6, 5);

      await expenses.add(
        amount: Money.parse('999'),
        categoryId: 1,
        date: currentMonth,
      );
      await expenses.add(
        amount: Money.parse('100'),
        categoryId: 1,
        date: lastMonth,
      );
      await expenses.add(
        amount: Money.parse('50'),
        categoryId: 1,
        date: lastMonth,
      );
      await expenses.add(
        amount: Money.parse('30'),
        categoryId: 1,
        date: twelveMonthsAgo,
      );

      final start = DateTime(now.year, now.month - 12, 1);
      final end = DateTime(now.year, now.month, 1);
      final rows = await expenses.listInRange(start, end);
      // Current-month row must never leak into the query window.
      expect(rows.any((e) => e.date.month == 6 && e.date.year == 2026), false);

      final months = bucketPastMonths(rows, now);
      expect(months.length, 12);
      expect(months.first.month, DateTime(2026, 5, 1)); // newest first
      expect(months.first.total, Money.fromMinor(15000));
      expect(months.first.count, 2);
      expect(months.last.month, DateTime(2025, 6, 1)); // oldest last
      expect(months.last.total, Money.fromMinor(3000));
      expect(months.last.count, 1);
    },
  );
}

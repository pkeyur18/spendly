import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/home/dashboard_providers.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository expenses;
  late Map<int, CategoryRow> byId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenses = ExpenseRepository(db);
    final cats = await CategoryRepository(db).watchAll().first;
    byId = {for (final c in cats) c.id: c};
  });
  tearDown(() => db.close());

  test('sumMoney is exact', () async {
    await expenses.add(amount: Money.parse('100.10'), categoryId: 1);
    await expenses.add(amount: Money.parse('0.20'), categoryId: 1);
    final rows = await expenses.watchMonth(DateTime.now()).first;
    expect(sumMoney(rows), Money.fromMinor(10030)); // 100.30 exactly
  });

  test('buildBreakdown sorts desc and fractions ~sum to 1', () async {
    final now = DateTime.now();
    await expenses.add(amount: Money.parse('100'), categoryId: 1, date: now);
    await expenses.add(amount: Money.parse('50'), categoryId: 1, date: now);
    await expenses.add(amount: Money.parse('200'), categoryId: 2, date: now);
    final rows = await expenses.watchMonth(now).first;

    final slices = buildBreakdown(rows, byId);
    expect(slices.length, 2);
    expect(slices.first.$1.id, 2); // 200 first (desc)
    expect(slices.first.$2, Money.fromMinor(20000));
    expect(slices[1].$1.id, 1); // 150
    final pctSum = slices.fold<double>(0, (a, s) => a + s.$3);
    expect(pctSum, closeTo(1.0, 0.0001));
  });

  test('trendBuckets: 6 bars, last is current month, totals land right', () async {
    final now = DateTime(2026, 6, 15);
    final lastMonth = DateTime(2026, 5, 10);
    await expenses.add(amount: Money.parse('300'), categoryId: 1, date: now);
    await expenses.add(amount: Money.parse('120'), categoryId: 1, date: lastMonth);
    final rows =
        await expenses.watchLastNMonths(6, now: now).first;

    final bars = trendBuckets(rows, 6, now);
    expect(bars.length, 6);
    expect(bars.last.$3, isTrue); // current month flagged
    expect(bars.last.$2, Money.fromMinor(30000)); // Jun 300
    expect(bars[4].$2, Money.fromMinor(12000)); // May 120
    expect(bars[3].$2, Money.zero); // Apr empty
  });

  test('empty inputs stay safe', () {
    expect(sumMoney(const []), Money.zero);
    expect(buildBreakdown(const [], byId), isEmpty);
    final bars = trendBuckets(const [], 6, DateTime(2026, 6, 1));
    expect(bars.length, 6);
    expect(bars.every((b) => b.$2 == Money.zero), isTrue);
  });
}

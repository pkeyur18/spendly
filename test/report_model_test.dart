import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/reports/report_model.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  Future<Map<int, CategoryRow>> byId() async {
    final cats = await db.select(db.categories).get();
    return {for (final c in cats) c.id: c};
  }

  // 10-day range: [Mar 1, Mar 11).
  final start = DateTime(2026, 3, 1);
  final end = DateTime(2026, 3, 11);

  Future<ReportData> build({required Money previousTotal}) async {
    final expenses = await repo.listInRange(start, end);
    return buildReport(
      start: start,
      end: end,
      expenses: expenses,
      previousTotal: previousTotal,
      categoriesById: await byId(),
    );
  }

  test('total, count and exact daily average over the range span', () async {
    await repo.add(
      amount: Money.parse('600'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
    );
    await repo.add(
      amount: Money.parse('400'),
      categoryId: 2,
      date: DateTime(2026, 3, 5),
    );

    final r = await build(previousTotal: Money.zero);
    expect(r.total, Money.fromMinor(100000)); // ₹1000
    expect(r.txnCount, 2);
    expect(r.dailyAverage, Money.fromMinor(10000)); // 100000 / 10 days
  });

  test('changePct vs previous period; null when previous is zero', () async {
    await repo.add(
      amount: Money.parse('1000'),
      categoryId: 1,
      date: DateTime(2026, 3, 3),
    );

    final up = await build(previousTotal: Money.parse('800'));
    expect(up.changePct, 25.0); // (1000-800)/800
    expect(up.changeUp, isTrue);

    final noPrev = await build(previousTotal: Money.zero);
    expect(noPrev.changePct, isNull);
  });

  test(
    'breakdown sorted desc, fractions sum ~100%, top category first',
    () async {
      await repo.add(
        amount: Money.parse('600'),
        categoryId: 1,
        date: DateTime(2026, 3, 2),
      );
      await repo.add(
        amount: Money.parse('400'),
        categoryId: 2,
        date: DateTime(2026, 3, 5),
      );

      final r = await build(previousTotal: Money.zero);
      expect(r.breakdown.map((s) => s.$1.id), [1, 2]); // 60% then 40%
      expect(r.topCategory!.$1.id, 1);
      final pctSum = r.breakdown.fold<double>(0, (a, s) => a + s.$3);
      expect((pctSum * 100).round(), 100);
    },
  );

  test('top5 keeps the five biggest, largest first', () async {
    for (final amt in ['100', '600', '300', '50', '450', '200']) {
      await repo.add(
        amount: Money.parse(amt),
        categoryId: 1,
        date: DateTime(2026, 3, 4),
      );
    }
    final r = await build(previousTotal: Money.zero);
    expect(r.top5.length, 5);
    expect(r.top5.map((e) => e.amountMinor), [
      60000,
      45000,
      30000,
      20000,
      10000,
    ]); // 5 dropped
  });

  test('empty range: zeros, no top category, still safe', () async {
    final r = await build(previousTotal: Money.parse('500'));
    expect(r.isEmpty, isTrue);
    expect(r.total, Money.zero);
    expect(r.dailyAverage, Money.zero);
    expect(r.topCategory, isNull);
    expect(r.changePct, -100.0); // spent nothing vs ₹500 before
  });

  test('weekly buckets split the range into 7-day windows', () async {
    await repo.add(
      amount: Money.parse('70'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
    ); // W1
    await repo.add(
      amount: Money.parse('30'),
      categoryId: 1,
      date: DateTime(2026, 3, 9),
    ); // W2
    final r = await build(previousTotal: Money.zero);
    expect(r.weekly.length, 2); // 10 days -> ceil(10/7)=2
    expect(r.weekly[0].$2, Money.fromMinor(7000));
    expect(r.weekly[1].$2, Money.fromMinor(3000));
    expect(r.weekly[1].$3, isTrue); // last bucket is "current"
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  test('add then read back exact amount (no float drift)', () async {
    final id = await repo.add(
      amount: Money.parse('24.35'),
      categoryId: 1,
      date: DateTime(2026, 3, 10),
    );
    final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    final row = rows.firstWhere((e) => e.id == id);
    expect(row.amount, Money.fromMinor(2435));
  });

  test('monthTotal sums minor units exactly', () async {
    await repo.add(amount: Money.parse('100.00'), categoryId: 1, date: DateTime(2026, 3, 2));
    await repo.add(amount: Money.parse('250.50'), categoryId: 1, date: DateTime(2026, 3, 20));
    final total = await repo.monthTotal(DateTime(2026, 3, 15));
    expect(total, Money.fromMinor(35050)); // 350.50
  });

  test('monthTotal excludes other months', () async {
    await repo.add(amount: Money.parse('100'), categoryId: 1, date: DateTime(2026, 3, 31, 23, 59));
    await repo.add(amount: Money.parse('100'), categoryId: 1, date: DateTime(2026, 4, 1, 0, 0));
    expect(await repo.monthTotal(DateTime(2026, 3, 1)), Money.fromMinor(10000));
  });

  test('totalsByCategory groups correctly', () async {
    await repo.add(amount: Money.parse('100'), categoryId: 1, date: DateTime(2026, 3, 5));
    await repo.add(amount: Money.parse('50'), categoryId: 1, date: DateTime(2026, 3, 6));
    await repo.add(amount: Money.parse('200'), categoryId: 2, date: DateTime(2026, 3, 7));
    final (start, end) = monthBounds(DateTime(2026, 3, 1));
    final totals = await repo.totalsByCategory(start, end);
    expect(totals[1], Money.fromMinor(15000));
    expect(totals[2], Money.fromMinor(20000));
  });

  test('watchInRange excludes out-of-range', () async {
    await repo.add(amount: Money.parse('10'), categoryId: 1, date: DateTime(2026, 3, 10));
    await repo.add(amount: Money.parse('10'), categoryId: 1, date: DateTime(2026, 5, 10));
    final rows =
        await repo.watchInRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1)).first;
    expect(rows.length, 1);
  });

  test('update and delete reflected', () async {
    final id = await repo.add(amount: Money.parse('100'), categoryId: 1, date: DateTime(2026, 3, 10));
    await repo.update(id, amount: Money.parse('175'));
    var rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    expect(rows.single.amount, Money.fromMinor(17500));

    await repo.delete(id);
    rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    expect(rows, isEmpty);
  });

  test('empty month totals to zero, not null', () async {
    expect(await repo.monthTotal(DateTime(2026, 9, 1)), Money.zero);
  });
}

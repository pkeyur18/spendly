import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/all_transactions_screen.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  test('groups a newest-first list into calendar-day buckets, order preserved', () async {
    // Two expenses on Mar 5 (added out of chronological order), one on Mar 3.
    await repo.add(amount: Money.parse('100'), categoryId: 1, date: DateTime(2026, 3, 3, 9));
    await repo.add(amount: Money.parse('200'), categoryId: 1, date: DateTime(2026, 3, 5, 8));
    await repo.add(amount: Money.parse('300'), categoryId: 1, date: DateTime(2026, 3, 5, 20));

    final expenses = await repo.listInRange(DateTime(2026, 3, 1), DateTime(2026, 3, 11));
    final groups = groupExpensesByDay(expenses);

    expect(groups.keys.toList(), [DateTime(2026, 3, 5), DateTime(2026, 3, 3)]);
    expect(groups[DateTime(2026, 3, 5)]!.map((e) => e.amount), [
      Money.parse('300'),
      Money.parse('200'),
    ]);
    expect(groups[DateTime(2026, 3, 3)]!.single.amount, Money.parse('100'));
  });
}

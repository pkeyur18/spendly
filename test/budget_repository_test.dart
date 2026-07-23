import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';

void main() {
  late AppDatabase db;
  late BudgetRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BudgetRepository(db);
  });
  tearDown(() => db.close());

  test('setOverall twice updates one row, never duplicates', () async {
    await repo.setOverall(Money.parse('40000'));
    await repo.setOverall(Money.parse('50000'));

    final all = await repo.watchAll().first;
    expect(all.length, 1);
    expect(all.single.categoryId, isNull);
    expect(all.single.amountMinor, Money.parse('50000').minor);
    expect(await repo.watchOverallBudget().first, Money.parse('50000'));
  });

  test(
    'per-category budgets are isolated from overall and each other',
    () async {
      await repo.setOverall(Money.parse('40000'));
      await repo.setForCategory(1, Money.parse('10000'));
      await repo.setForCategory(2, Money.parse('6000'));
      await repo.setForCategory(1, Money.parse('12000')); // update, not insert

      final all = await repo.watchAll().first;
      expect(all.length, 3); // overall + cat1 + cat2
      final cat1 = all.firstWhere((b) => b.categoryId == 1);
      expect(cat1.amountMinor, Money.parse('12000').minor);
      // overall untouched
      expect(await repo.watchOverallBudget().first, Money.parse('40000'));
    },
  );

  test('clearForCategory removes only that category budget', () async {
    await repo.setForCategory(1, Money.parse('10000'));
    await repo.setForCategory(2, Money.parse('6000'));
    await repo.clearForCategory(1);

    final all = await repo.watchAll().first;
    expect(all.map((b) => b.categoryId), [2]);
  });
}

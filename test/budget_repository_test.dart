import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';

void main() {
  late AppDatabase db;
  late BudgetRepository repo;

  final march = DateTime(2026, 3, 1);
  final april = DateTime(2026, 4, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BudgetRepository(db);
  });
  tearDown(() => db.close());

  test('monthKeyFor zero-pads single-digit months', () {
    expect(monthKeyFor(DateTime(2026, 3, 1)), '2026-03');
    expect(monthKeyFor(DateTime(2026, 11, 1)), '2026-11');
  });

  test('setOverall twice in the same month updates one row, never duplicates', () async {
    await repo.setOverall(march, Money.parse('40000'));
    await repo.setOverall(march, Money.parse('50000'));

    final all = await repo.watchAllForMonth(march).first;
    expect(all.length, 1);
    expect(all.single.categoryId, isNull);
    expect(all.single.amountMinor, Money.parse('50000').minor);
    expect(await repo.watchOverallBudget(march).first, Money.parse('50000'));
  });

  test('per-category budgets are isolated from overall and each other', () async {
    await repo.setOverall(march, Money.parse('40000'));
    await repo.setForCategory(march, 1, Money.parse('10000'));
    await repo.setForCategory(march, 2, Money.parse('6000'));
    await repo.setForCategory(march, 1, Money.parse('12000')); // update, not insert

    final all = await repo.watchAllForMonth(march).first;
    expect(all.length, 3); // overall + cat1 + cat2
    final cat1 = all.firstWhere((b) => b.categoryId == 1);
    expect(cat1.amountMinor, Money.parse('12000').minor);
    expect(await repo.watchOverallBudget(march).first, Money.parse('40000'));
  });

  test('clearForCategory removes only that category budget in that month', () async {
    await repo.setForCategory(march, 1, Money.parse('10000'));
    await repo.setForCategory(march, 2, Money.parse('6000'));
    await repo.clearForCategory(march, 1);

    final all = await repo.watchAllForMonth(march).first;
    expect(all.map((b) => b.categoryId), [2]);
  });

  test('budgets are scoped to their month, not leaked across months', () async {
    await repo.setOverall(march, Money.parse('5000'));
    await repo.setForCategory(march, 1, Money.parse('1000'));

    expect((await repo.watchAllForMonth(march).first).length, 2);
    expect(await repo.watchAllForMonth(april).first, isEmpty);
  });

  test('carryForward copies overall + per-category rows into the target month', () async {
    await repo.setOverall(march, Money.parse('5000'));
    await repo.setForCategory(march, 1, Money.parse('1000'));
    await repo.setForCategory(march, 2, Money.parse('500'));

    await repo.carryForward(fromMonth: march, toMonth: april);

    final aprilRows = await repo.watchAllForMonth(april).first;
    expect(aprilRows.length, 3);
    expect(await repo.watchOverallBudget(april).first, Money.parse('5000'));
  });

  test('carryForward overwrites an existing row in the target month rather than duplicating it', () async {
    await repo.setForCategory(march, 1, Money.parse('1000'));
    await repo.setForCategory(april, 1, Money.parse('50'));

    await repo.carryForward(fromMonth: march, toMonth: april);

    final aprilRows = await repo.watchAllForMonth(april).first;
    expect(aprilRows.length, 1);
    expect(Money.fromMinor(aprilRows.single.amountMinor), Money.parse('1000'));
  });
}

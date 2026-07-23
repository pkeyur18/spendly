import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('resetToDefaults wipes expenses/budgets/settings and reseeds categories', () async {
    final catRepo = CategoryRepository(db);
    final expRepo = ExpenseRepository(db);
    final budgetRepo = BudgetRepository(db);

    final extraCatId = await catRepo.create(
      name: 'Extra',
      icon: '⭐',
      colorValue: 0xFF6366F1,
    );
    await expRepo.add(
      amount: Money.parse('24.50'),
      categoryId: extraCatId,
      date: DateTime(2026, 7, 1),
    );
    await budgetRepo.setOverall(Money.parse('40000'));
    await SettingsRepository(db).set(SettingsRepository.profileNameKey, 'Ada');

    await db.resetToDefaults();

    final expenses = await db.select(db.expenses).get();
    final budgets = await db.select(db.budgets).get();
    final settings = await db.select(db.settings).get();
    final categories = await db.select(db.categories).get();

    expect(expenses, isEmpty);
    expect(budgets, isEmpty);
    expect(settings, isEmpty);
    expect(categories.length, 8); // the shipped default categories
    expect(categories.every((c) => c.isDefault), isTrue);
  });
}

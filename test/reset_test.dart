import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/expenses/receipt_repository.dart';

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
    final expenseId = await expRepo.add(
      amount: Money.parse('24.50'),
      categoryId: extraCatId,
      date: DateTime(2026, 7, 1),
    );
    await budgetRepo.setOverall(DateTime(2026, 7, 1), Money.parse('40000'));
    await SettingsRepository(db).set(SettingsRepository.profileNameKey, 'Ada');
    await ReceiptRepository(
      db,
    ).set(expenseId, Uint8List.fromList([1, 2, 3]));

    await db.resetToDefaults();

    final expenses = await db.select(db.expenses).get();
    final budgets = await db.select(db.budgets).get();
    final settings = await db.select(db.settings).get();
    final categories = await db.select(db.categories).get();
    final receipts = await db.select(db.expenseReceipts).get();

    expect(expenses, isEmpty);
    expect(budgets, isEmpty);
    expect(settings, isEmpty);
    expect(categories.length, 18); // the shipped default categories
    expect(categories.every((c) => c.isDefault), isTrue);
    // Without this, "Delete all data" would leave every receipt photo behind
    // as a permanent orphan — the one case pruneOrphanedReceipts can't catch
    // on its own, since a fresh install never runs it against pre-reset data.
    expect(receipts, isEmpty);
  });
}

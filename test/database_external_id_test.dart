import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/tags/tag_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() {
    db.close();
  });

  test(
    'new rows created through each repository get a non-null externalId',
    () async {
      final catId = await CategoryRepository(
        db,
      ).create(name: 'Test', icon: '⭐', colorValue: 0xFF6366F1);
      final tagId = await TagRepository(
        db,
      ).create(name: 'Trip', colorValue: 0xFF6366F1);
      await ExpenseRepository(db).add(
        amount: Money.parse('10'),
        categoryId: catId,
        date: DateTime(2026, 7, 1),
      );
      await BudgetRepository(
        db,
      ).setOverall(DateTime(2026, 7, 1), Money.parse('1000'));

      final category = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(catId))).getSingle();
      final tag = await (db.select(
        db.tags,
      )..where((t) => t.id.equals(tagId))).getSingle();
      final expense = await db.select(db.expenses).getSingle();
      final budget = await db.select(db.budgets).getSingle();

      expect(category.externalId, isNotNull);
      expect(tag.externalId, isNotNull);
      expect(expense.externalId, isNotNull);
      expect(budget.externalId, isNotNull);
    },
  );

  test(
    'backfillExternalIds populates every null externalId with a distinct value, '
    'leaving already-set ones untouched',
    () async {
      final keptId = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Already tagged',
              icon: '🏷️',
              colorValue: 1,
              externalId: const Value('keep-me'),
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Legacy A',
              icon: '🅰️',
              colorValue: 2,
              externalId: const Value(null),
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Legacy B',
              icon: '🅱️',
              colorValue: 3,
              externalId: const Value(null),
            ),
          );

      await backfillExternalIds(db);

      final rows = await db.select(db.categories).get();
      final kept = rows.singleWhere((r) => r.id == keptId);
      final legacyA = rows.singleWhere((r) => r.name == 'Legacy A');
      final legacyB = rows.singleWhere((r) => r.name == 'Legacy B');

      expect(kept.externalId, 'keep-me'); // untouched
      expect(legacyA.externalId, isNotNull);
      expect(legacyB.externalId, isNotNull);
      expect(legacyA.externalId, isNot(legacyB.externalId)); // distinct
    },
  );
}

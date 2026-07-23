import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db);
  });
  tearDown(() => db.close());

  test('seeds 8 default categories on create (FR-8)', () async {
    final cats = await repo.watchAll().first;
    expect(cats.length, 8);
    expect(
      cats.map((c) => c.name),
      containsAll(['Food', 'Travel', 'Bills', 'Other']),
    );
    expect(cats.every((c) => c.isDefault), isTrue);
  });

  test('create appends after existing sortOrder', () async {
    final id = await repo.create(
      name: 'Test',
      icon: '⭐',
      colorValue: 0xFF6366F1,
    );
    final cats = await repo.watchAll().first;
    final created = cats.firstWhere((c) => c.id == id);
    expect(created.sortOrder, 8); // after the 0-7 defaults
  });

  test('archive hides from active but keeps the row (FR-11)', () async {
    await repo.archive(1);
    final active = await repo.watchActive().first;
    final all = await repo.watchAll().first;
    expect(active.any((c) => c.id == 1), isFalse);
    expect(all.any((c) => c.id == 1), isTrue); // never deleted
  });

  test('archived category referenced by an expense is preserved', () async {
    await ExpenseRepository(db).add(amount: Money.parse('100'), categoryId: 1);
    await repo.archive(1);
    final all = await repo.watchAll().first;
    expect(all.firstWhere((c) => c.id == 1).isArchived, isTrue);
  });

  test('reorder rewrites sortOrder', () async {
    // Reverse the first three ids.
    await repo.reorder([3, 2, 1]);
    final cats = await repo.watchAll().first;
    expect(cats.first.id, 3); // sortOrder 0 now belongs to id 3
    expect(cats[1].id, 2);
    expect(cats[2].id, 1);
  });
}

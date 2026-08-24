import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/expenses/receipt_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository expenses;
  late ReceiptRepository receipts;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenses = ExpenseRepository(db);
    receipts = ReceiptRepository(db);
  });
  tearDown(() => db.close());

  Future<int> seedExpense() =>
      expenses.add(amount: Money.parse('240'), categoryId: 1);

  test('no receipt is null, not an error', () async {
    final id = await seedExpense();
    expect(await receipts.forExpense(id), isNull);
  });

  test('set then read returns the same bytes', () async {
    final id = await seedExpense();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await receipts.set(id, bytes);
    expect(await receipts.forExpense(id), bytes);
  });

  test('setting again replaces rather than adding a second row', () async {
    final id = await seedExpense();
    await receipts.set(id, Uint8List.fromList([1]));
    await receipts.set(id, Uint8List.fromList([2, 2]));

    expect(await receipts.forExpense(id), [2, 2]);
    final rows = await db.select(db.expenseReceipts).get();
    expect(rows, hasLength(1));
  });

  test('setting null clears an existing receipt', () async {
    final id = await seedExpense();
    await receipts.set(id, Uint8List.fromList([1, 2, 3]));
    await receipts.set(id, null);

    expect(await receipts.forExpense(id), isNull);
    expect(await db.select(db.expenseReceipts).get(), isEmpty);
  });

  test('setting null with nothing to clear does not throw', () async {
    final id = await seedExpense();
    await receipts.set(id, null);
    expect(await receipts.forExpense(id), isNull);
  });

  test('each expense keeps its own receipt independently', () async {
    final a = await seedExpense();
    final b = await seedExpense();
    await receipts.set(a, Uint8List.fromList([1]));
    await receipts.set(b, Uint8List.fromList([2]));

    expect(await receipts.forExpense(a), [1]);
    expect(await receipts.forExpense(b), [2]);
  });

  test('watchExpenseIdsWithReceipt returns ids, not bytes', () async {
    final withPhoto = await seedExpense();
    final withoutPhoto = await seedExpense();
    await receipts.set(withPhoto, Uint8List.fromList([9, 9, 9]));

    final ids = await receipts.watchExpenseIdsWithReceipt().first;
    expect(ids, {withPhoto});
    expect(ids.contains(withoutPhoto), isFalse);
  });

  test('the id set updates live after a later set/clear', () async {
    final id = await seedExpense();
    final stream = receipts.watchExpenseIdsWithReceipt();
    final emissions = <Set<int>>[];
    final sub = stream.listen(emissions.add);
    addTearDown(sub.cancel);

    await receipts.set(id, Uint8List.fromList([1]));
    await pumpEventQueue();
    await receipts.set(id, null);
    await pumpEventQueue();

    expect(emissions.first, isEmpty);
    expect(emissions.any((s) => s.contains(id)), isTrue);
    expect(emissions.last, isEmpty);
  });

  group('pruneOrphanedReceipts', () {
    test('deletes a receipt whose expense was deleted', () async {
      final id = await seedExpense();
      await receipts.set(id, Uint8List.fromList([1, 2, 3]));
      await expenses.delete(id);

      await db.pruneOrphanedReceipts();

      expect(await db.select(db.expenseReceipts).get(), isEmpty);
    });

    test('leaves a receipt alone while its expense still exists', () async {
      final id = await seedExpense();
      await receipts.set(id, Uint8List.fromList([1, 2, 3]));

      await db.pruneOrphanedReceipts();

      expect(await receipts.forExpense(id), [1, 2, 3]);
    });

    test('an undo within the window survives a prune that never runs', () async {
      // Mirrors the real undo flow: delete() leaves the receipt row in
      // place, and restore() reuses the same id, so the receipt reattaches
      // with no explicit handling — as long as nothing pruned in between.
      final id = await seedExpense();
      final original = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals(id))).getSingle();
      await receipts.set(original.id, Uint8List.fromList([7, 7]));

      await expenses.delete(original.id);
      await expenses.restore(original);

      expect(await receipts.forExpense(original.id), [7, 7]);
    });
  });
}

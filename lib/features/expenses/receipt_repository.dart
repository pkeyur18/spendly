import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';

/// Receipt photos (schema v11) — see [ExpenseReceipts]' doc comment for why
/// these live in their own table rather than a column on [Expenses].
class ReceiptRepository {
  ReceiptRepository(this._db);
  final AppDatabase _db;

  Future<Uint8List?> forExpense(int expenseId) async {
    final row = await (_db.select(
      _db.expenseReceipts,
    )..where((t) => t.expenseId.equals(expenseId))).getSingleOrNull();
    return row?.photoBytes;
  }

  /// Live existence set, not the bytes — feeds a lightweight indicator on any
  /// screen that lists many expenses at once, without dragging photo bytes
  /// into a paginated read the way a column on [Expenses] would have.
  Stream<Set<int>> watchExpenseIdsWithReceipt() {
    final query = _db.selectOnly(_db.expenseReceipts)
      ..addColumns([_db.expenseReceipts.expenseId]);
    return query.watch().map(
      (rows) => {for (final r in rows) r.read(_db.expenseReceipts.expenseId)!},
    );
  }

  /// Sets (or clears, when [bytes] is null) the receipt for [expenseId].
  ///
  /// `insertOrReplace` rather than a manual check-then-insert/update: SQLite's
  /// `INSERT OR REPLACE` honors the table's unique index on `expenseId` (not
  /// only its primary key), so replacing an existing photo is one statement,
  /// not two round trips with a race between them.
  Future<void> set(int expenseId, Uint8List? bytes) async {
    if (bytes == null) {
      await (_db.delete(
        _db.expenseReceipts,
      )..where((t) => t.expenseId.equals(expenseId))).go();
      return;
    }
    await _db
        .into(_db.expenseReceipts)
        .insert(
          ExpenseReceiptsCompanion.insert(
            expenseId: expenseId,
            photoBytes: bytes,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }
}

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(ref.watch(databaseProvider)),
);

/// Live set of expense ids that currently have a receipt attached.
final expenseIdsWithReceiptProvider = StreamProvider<Set<int>>(
  (ref) => ref.watch(receiptRepositoryProvider).watchExpenseIdsWithReceipt(),
);

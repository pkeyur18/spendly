import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';
import '../reports/report_providers.dart' show DateRange;

/// Income CRUD (schema v15) — see [LedgerEntries]'s doc comment for why this
/// lives apart from [ExpenseRepository]. Entries are hard-deleted: unlike
/// categories/tags/accounts, nothing else in the schema references a ledger
/// entry by id, so there's no history to protect by archiving instead.
class LedgerRepository {
  LedgerRepository(this._db);
  final AppDatabase _db;

  Future<int> addIncome({
    required Money amount,
    required DateTime date,
    int? accountId,
    String? sourceLabel,
    String? note,
  }) => _db
      .into(_db.ledgerEntries)
      .insert(
        LedgerEntriesCompanion.insert(
          amountMinor: amount.minor,
          date: date,
          accountId: Value(accountId),
          sourceLabel: Value(sourceLabel),
          note: Value(note),
        ),
      );

  Future<void> update(
    int id, {
    Money? amount,
    DateTime? date,
    int? accountId,
    bool clearAccount = false,
    String? sourceLabel,
    String? note,
  }) => (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(id))).write(
    LedgerEntriesCompanion(
      amountMinor: amount == null ? const Value.absent() : Value(amount.minor),
      date: date == null ? const Value.absent() : Value(date),
      accountId: clearAccount
          ? const Value(null)
          : (accountId == null ? const Value.absent() : Value(accountId)),
      sourceLabel: sourceLabel == null ? const Value.absent() : Value(sourceLabel),
      note: note == null ? const Value.absent() : Value(note),
    ),
  );

  Future<void> delete(int id) =>
      (_db.delete(_db.ledgerEntries)..where((t) => t.id.equals(id))).go();

  /// Puts a deleted row back exactly as it was — same id/externalId, backs
  /// the undo-a-delete snackbar. Same trick as `ExpenseRepository.restore`.
  Future<void> restore(LedgerEntryRow row) =>
      _db.into(_db.ledgerEntries).insert(row.toCompanion(false));

  Stream<List<LedgerEntryRow>> watchAll() {
    return (_db.select(_db.ledgerEntries)..orderBy(
          [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)],
        ))
        .watch();
  }

  Stream<List<LedgerEntryRow>> watchInRange(DateTime start, DateTime end) {
    return (_db.select(_db.ledgerEntries)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
          ..orderBy(
            [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)],
          ))
        .watch();
  }

  Stream<Money> watchTotalInRange(DateTime start, DateTime end) {
    final sum = _db.ledgerEntries.amountMinor.sum();
    final query = _db.selectOnly(_db.ledgerEntries)
      ..addColumns([sum])
      ..where(
        _db.ledgerEntries.date.isBiggerOrEqualValue(start) &
            _db.ledgerEntries.date.isSmallerThanValue(end),
      );
    return query.watchSingle().map((r) => Money.fromMinor(r.read(sum) ?? 0));
  }
}

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(databaseProvider)),
);

final allIncomeProvider = StreamProvider<List<LedgerEntryRow>>(
  (ref) => ref.watch(ledgerRepositoryProvider).watchAll(),
);

/// Income total for an arbitrary range — watched independently by Monthly
/// Recap and the report screens alongside their own expense total, then
/// combined via `cashflow_math.dart`. Kept as a sibling provider rather than
/// folded into `ReportData`/`buildReport`: those stay expense-only by the
/// same "separate ledger table" decision this whole table exists for.
final incomeTotalByRangeProvider = StreamProvider.family<Money, DateRange>(
  (ref, range) =>
      ref.watch(ledgerRepositoryProvider).watchTotalInRange(range.$1, range.$2),
);

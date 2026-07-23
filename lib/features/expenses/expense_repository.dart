import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';

/// Expense CRUD + money-math queries (FR-1, FR-6). All amounts flow through
/// [Money] (integer minor units) — never a float.
class ExpenseRepository {
  ExpenseRepository(this._db);
  final AppDatabase _db;

  Future<int> add({
    required Money amount,
    required int categoryId,
    DateTime? date,
    String? note,
    String? paymentMethod,
    bool isRecurring = false,
    Recurrence? recurrence,
  }) {
    return _db.into(_db.expenses).insert(
          ExpensesCompanion.insert(
            amountMinor: amount.minor,
            categoryId: categoryId,
            date: date ?? DateTime.now(),
            note: Value(note),
            paymentMethod: Value(paymentMethod),
            isRecurring: Value(isRecurring),
            recurrence: Value(recurrence),
          ),
        );
  }

  Future<void> update(
    int id, {
    Money? amount,
    int? categoryId,
    DateTime? date,
    Value<String?> note = const Value.absent(),
    Value<String?> paymentMethod = const Value.absent(),
    bool? isRecurring,
    Value<Recurrence?> recurrence = const Value.absent(),
  }) async {
    await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
      ExpensesCompanion(
        amountMinor: amount == null ? const Value.absent() : Value(amount.minor),
        categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
        date: date == null ? const Value.absent() : Value(date),
        note: note,
        paymentMethod: paymentMethod,
        isRecurring:
            isRecurring == null ? const Value.absent() : Value(isRecurring),
        recurrence: recurrence,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();

  /// Expenses with date in [start, end), newest first.
  Stream<List<ExpenseRow>> watchInRange(DateTime start, DateTime end) {
    return (_db.select(_db.expenses)
          ..where((t) => t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<ExpenseRow>> watchMonth(DateTime month) {
    final (start, end) = monthBounds(month);
    return watchInRange(start, end);
  }

  /// Expenses across the last [n] calendar months up to (and including) [now]'s
  /// month — feeds the trend chart. Bucket by month in Dart.
  Stream<List<ExpenseRow>> watchLastNMonths(int n, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final start = DateTime(ref.year, ref.month - (n - 1), 1);
    final end = DateTime(ref.year, ref.month + 1, 1);
    return watchInRange(start, end);
  }

  /// Exact total across a calendar month (sum of minor units).
  Future<Money> monthTotal(DateTime month) {
    final (start, end) = monthBounds(month);
    return totalInRange(start, end);
  }

  Future<Money> totalInRange(DateTime start, DateTime end) async {
    final sum = _db.expenses.amountMinor.sum();
    final row = await (_db.selectOnly(_db.expenses)
          ..addColumns([sum])
          ..where(_db.expenses.date.isBiggerOrEqualValue(start) &
              _db.expenses.date.isSmallerThanValue(end)))
        .getSingle();
    return Money.fromMinor(row.read(sum) ?? 0);
  }

  /// All expenses in [start, end), newest first — reports derive total, count,
  /// per-category, top-5 and weekly trend from this single list (FR-20).
  Future<List<ExpenseRow>> listInRange(DateTime start, DateTime end) {
    return (_db.select(_db.expenses)
          ..where((t) => t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Spend per category in [start, end) — feeds the donut / reports.
  Future<Map<int, Money>> totalsByCategory(DateTime start, DateTime end) async {
    final sum = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.categoryId, sum])
      ..where(_db.expenses.date.isBiggerOrEqualValue(start) &
          _db.expenses.date.isSmallerThanValue(end))
      ..groupBy([_db.expenses.categoryId]);
    final rows = await query.get();
    return {
      for (final r in rows)
        r.read(_db.expenses.categoryId)!: Money.fromMinor(r.read(sum) ?? 0),
    };
  }
}

/// Half-open [start, end) bounds for the calendar month containing [month].
(DateTime, DateTime) monthBounds(DateTime month) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);
  return (start, end);
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(databaseProvider)),
);

final currentMonthExpensesProvider = StreamProvider<List<ExpenseRow>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchMonth(DateTime.now()),
);

final currentMonthTotalProvider = FutureProvider<Money>(
  (ref) => ref.watch(expenseRepositoryProvider).monthTotal(DateTime.now()),
);

final currentMonthCategoryTotalsProvider = FutureProvider<Map<int, Money>>(
  (ref) {
    final (start, end) = monthBounds(DateTime.now());
    return ref.watch(expenseRepositoryProvider).totalsByCategory(start, end);
  },
);

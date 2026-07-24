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
    int? tagId,
  }) {
    return _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            amountMinor: amount.minor,
            categoryId: categoryId,
            date: date ?? DateTime.now(),
            note: Value(note),
            paymentMethod: Value(paymentMethod),
            isRecurring: Value(isRecurring),
            recurrence: Value(recurrence),
            tagId: Value(tagId),
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
    Value<int?> tagId = const Value.absent(),
  }) async {
    await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
      ExpensesCompanion(
        amountMinor: amount == null
            ? const Value.absent()
            : Value(amount.minor),
        categoryId: categoryId == null
            ? const Value.absent()
            : Value(categoryId),
        date: date == null ? const Value.absent() : Value(date),
        note: note,
        paymentMethod: paymentMethod,
        isRecurring: isRecurring == null
            ? const Value.absent()
            : Value(isRecurring),
        recurrence: recurrence,
        tagId: tagId,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();

  /// Expenses with date in [start, end), newest first.
  Stream<List<ExpenseRow>> watchInRange(DateTime start, DateTime end) {
    return (_db.select(_db.expenses)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
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

  /// Exact total for the calendar day containing [day] — feeds the "today"
  /// widget (FR-26). Reuses the range-sum primitive with day bounds.
  Future<Money> todayTotal([DateTime? day]) {
    final (start, end) = dayBounds(day ?? DateTime.now());
    return totalInRange(start, end);
  }

  Future<Money> totalInRange(DateTime start, DateTime end) async {
    final sum = _db.expenses.amountMinor.sum();
    final row =
        await (_db.selectOnly(_db.expenses)
              ..addColumns([sum])
              ..where(
                _db.expenses.date.isBiggerOrEqualValue(start) &
                    _db.expenses.date.isSmallerThanValue(end),
              ))
            .getSingle();
    return Money.fromMinor(row.read(sum) ?? 0);
  }

  /// All expenses in [start, end), newest first — reports derive total, count,
  /// per-category, top-5 and weekly trend from this single list (FR-20).
  Future<List<ExpenseRow>> listInRange(DateTime start, DateTime end) {
    return (_db.select(_db.expenses)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// (date, categoryId) for every expense, live — feeds Profile's lifetime
  /// stats (FR-51). Only these two columns, not full rows.
  Stream<List<(DateTime, int)>> watchLifetimeStats() {
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.date, _db.expenses.categoryId]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          (r.read(_db.expenses.date)!, r.read(_db.expenses.categoryId)!),
      ],
    );
  }

  /// Spend per category in [start, end) — feeds the donut / reports.
  Future<Map<int, Money>> totalsByCategory(DateTime start, DateTime end) async {
    final sum = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.categoryId, sum])
      ..where(
        _db.expenses.date.isBiggerOrEqualValue(start) &
            _db.expenses.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.expenses.categoryId]);
    final rows = await query.get();
    return {
      for (final r in rows)
        r.read(_db.expenses.categoryId)!: Money.fromMinor(r.read(sum) ?? 0),
    };
  }

  /// Expenses tagged with [tagId] (e.g. all spend on one trip), newest first.
  Stream<List<ExpenseRow>> watchByTag(int tagId) {
    return (_db.select(_db.expenses)
          ..where((t) => t.tagId.equals(tagId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Live count of expenses carrying [tagId] — feeds the Tags report list;
  /// `.watch()` (not `.get()`) so it re-emits on every write, same as
  /// [watchByTag] and unlike the one-shot `totalsByCategory`.
  Stream<int> watchCountByTag(int tagId) {
    final countExpr = _db.expenses.id.count();
    return (_db.selectOnly(_db.expenses)
          ..addColumns([countExpr])
          ..where(_db.expenses.tagId.equals(tagId)))
        .map((row) => row.read(countExpr) ?? 0)
        .watchSingle();
  }

  /// Live lifetime spend per tag — feeds the Tags report list. Untagged
  /// expenses (tagId null) are excluded, not grouped under a null key.
  /// `.watch()` so the list stays current after tagging/untagging/adding an
  /// expense, instead of only refreshing on next screen mount.
  Stream<Map<int, Money>> watchTotalsByTag() {
    final sum = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.tagId, sum])
      ..where(_db.expenses.tagId.isNotNull())
      ..groupBy([_db.expenses.tagId]);
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.expenses.tagId)!: Money.fromMinor(r.read(sum) ?? 0),
      },
    );
  }
}

/// Half-open [start, end) bounds for the calendar month containing [month].
(DateTime, DateTime) monthBounds(DateTime month) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);
  return (start, end);
}

/// Half-open [start, end) bounds for the calendar day containing [day].
(DateTime, DateTime) dayBounds(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  return (start, end);
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(databaseProvider)),
);

/// Raw expense list for a half-open [start, end) range, newest first — feeds
/// [AllTransactionsScreen] (no need for the heavier [ReportData] there).
final expensesInRangeProvider =
    StreamProvider.family<List<ExpenseRow>, (DateTime, DateTime)>(
      (ref, range) =>
          ref.watch(expenseRepositoryProvider).watchInRange(range.$1, range.$2),
    );

final currentMonthExpensesProvider = StreamProvider<List<ExpenseRow>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchMonth(DateTime.now()),
);

final currentMonthTotalProvider = FutureProvider<Money>(
  (ref) => ref.watch(expenseRepositoryProvider).monthTotal(DateTime.now()),
);

final currentMonthCategoryTotalsProvider = FutureProvider<Map<int, Money>>((
  ref,
) {
  final (start, end) = monthBounds(DateTime.now());
  return ref.watch(expenseRepositoryProvider).totalsByCategory(start, end);
});

/// Live lifetime spend per tag — feeds the Tags report list.
final tagTotalsProvider = StreamProvider<Map<int, Money>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchTotalsByTag(),
);

/// Live expense count for one tag — feeds the Tags report list.
final tagExpenseCountProvider = StreamProvider.family<int, int>(
  (ref, tagId) => ref.watch(expenseRepositoryProvider).watchCountByTag(tagId),
);

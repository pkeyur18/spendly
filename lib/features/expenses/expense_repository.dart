import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';
import '../categories/category_repository.dart';

/// A search box turned into the three things it can match. Empty [text] means
/// "no search" and every field is inert.
typedef ExpenseQuery = ({String? text, int? amountMinor, Set<int> categoryIds});

const _emptyQuery = (
  text: null,
  amountMinor: null,
  categoryIds: <int>{},
);

/// Splits a raw search box into a note match, an amount match, and the set of
/// categories whose name matches — combined with OR when the query runs, so
/// typing "food", "lunch" or "240" all find something sensible.
///
/// Pure and category-name matching happens here rather than in SQL because
/// category names live in a table the expense queries don't join; the id set
/// is small and already in memory.
ExpenseQuery parseExpenseQuery(String raw, Iterable<CategoryRow> categories) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return _emptyQuery;

  int? amountMinor;
  try {
    final money = Money.parse(trimmed);
    if (money.minor > 0) amountMinor = money.minor;
  } on FormatException {
    // Not a number — note and category matching still apply.
  }

  final lower = trimmed.toLowerCase();
  return (
    text: trimmed,
    amountMinor: amountMinor,
    categoryIds: {
      for (final c in categories)
        if (c.name.toLowerCase().contains(lower)) c.id,
    },
  );
}

/// Expense CRUD + money-math queries (FR-1, FR-6). All amounts flow through
/// [Money] (integer minor units) — never a float.
class ExpenseRepository {
  ExpenseRepository(this._db);
  final AppDatabase _db;

  /// [amount] is ALWAYS home currency. For a trip abroad the caller converts
  /// first (see `lib/core/money/fx.dart`) and passes the original alongside as
  /// [fxCurrency] + [fxAmount] — this repository stores what it is given and
  /// never does rate math.
  Future<int> add({
    required Money amount,
    required int categoryId,
    DateTime? date,
    String? note,
    String? paymentMethod,
    bool isRecurring = false,
    Recurrence? recurrence,
    DateTime? nextDueDate,
    DateTime? recurrenceEndDate,
    int? tagId,
    int? accountId,
    String? fxCurrency,
    Money? fxAmount,
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
            nextDueDate: Value(nextDueDate),
            recurrenceEndDate: Value(recurrenceEndDate),
            tagId: Value(tagId),
            accountId: Value(accountId),
            fxCurrency: Value(fxCurrency),
            fxAmountMinor: Value(fxAmount?.minor),
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
    Value<DateTime?> nextDueDate = const Value.absent(),
    Value<DateTime?> recurrenceEndDate = const Value.absent(),
    Value<int?> tagId = const Value.absent(),
    Value<int?> accountId = const Value.absent(),
    Value<String?> fxCurrency = const Value.absent(),
    Value<Money?> fxAmount = const Value.absent(),
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
        nextDueDate: nextDueDate,
        recurrenceEndDate: recurrenceEndDate,
        tagId: tagId,
        accountId: accountId,
        fxCurrency: fxCurrency,
        fxAmountMinor: fxAmount.present
            ? Value(fxAmount.value?.minor)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();

  /// Puts a deleted row back exactly as it was — same id, same `externalId`,
  /// same timestamps. Backs the undo-a-delete snackbar.
  ///
  /// Re-using the original id is safe because the table is
  /// `PRIMARY KEY AUTOINCREMENT`, so SQLite never hands a freed id to a new
  /// row (asserted in `expense_repository_test.dart`, not assumed). Keeping
  /// `externalId` matters just as much: a fresh one would read as a different
  /// record to a backup Merge, so an undo would quietly fork the row across
  /// devices.
  Future<void> restore(ExpenseRow row) =>
      _db.into(_db.expenses).insert(row.toCompanion(false));

  /// Expenses with date in [start, end), newest first. Pass [limit] to cap the
  /// rows loaded (lazy pagination for long lists); null = whole range. Pass
  /// [categoryIds] to restrict to those categories; null/empty = no filter.
  /// Pass [search] to additionally match note text, exact amount, or category
  /// name — see [parseExpenseQuery].
  ///
  /// The search runs in SQL rather than over the returned list because the
  /// list is paginated: filtering in Dart would only ever search the page
  /// that happened to be loaded.
  Stream<List<ExpenseRow>> watchInRange(
    DateTime start,
    DateTime end, {
    int? limit,
    Set<int>? categoryIds,
    ExpenseQuery? search,
  }) {
    final query = _db.select(_db.expenses)
      ..where(
        (t) =>
            t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(end),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    if (categoryIds != null && categoryIds.isNotEmpty) {
      query.where((t) => t.categoryId.isIn(categoryIds));
    }
    final text = search?.text;
    if (text != null) {
      // OR across the three kinds of match, ANDed with the range and any
      // explicit category filter above.
      //
      // ponytail: `%`/`_` typed into the box act as LIKE wildcards instead of
      // literals. Parameterized either way, so this is a cosmetic quirk, not
      // an injection path — add escaping if anyone ever notices.
      query.where((t) {
        var predicate = t.note.lower().contains(text.toLowerCase());
        final amountMinor = search!.amountMinor;
        if (amountMinor != null) {
          predicate = predicate | t.amountMinor.equals(amountMinor);
        }
        if (search.categoryIds.isNotEmpty) {
          predicate = predicate | t.categoryId.isIn(search.categoryIds);
        }
        return predicate;
      });
    }
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// Distinct category ids with at least one expense in [start, end) — feeds
  /// the category filter chips on [AllTransactionsScreen] so only categories
  /// actually present in the range are offered.
  Stream<Set<int>> distinctCategoryIdsInRange(DateTime start, DateTime end) {
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.categoryId])
      ..where(
        _db.expenses.date.isBiggerOrEqualValue(start) &
            _db.expenses.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.expenses.categoryId]);
    return query.watch().map(
      (rows) => {for (final r in rows) r.read(_db.expenses.categoryId)!},
    );
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

  /// Exact total across a calendar month (sum of minor units). Pass
  /// [excludeCategoryIds] to leave "ignored for budget" categories out.
  Future<Money> monthTotal(DateTime month, {Set<int>? excludeCategoryIds}) {
    final (start, end) = monthBounds(month);
    return totalInRange(start, end, excludeCategoryIds: excludeCategoryIds);
  }

  /// Exact total for the calendar day containing [day] — feeds the "today"
  /// widget (FR-26). Reuses the range-sum primitive with day bounds.
  Future<Money> todayTotal([DateTime? day, Set<int>? excludeCategoryIds]) {
    final (start, end) = dayBounds(day ?? DateTime.now());
    return totalInRange(start, end, excludeCategoryIds: excludeCategoryIds);
  }

  Future<Money> totalInRange(
    DateTime start,
    DateTime end, {
    Set<int>? excludeCategoryIds,
  }) async {
    final sum = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([sum])
      ..where(
        _db.expenses.date.isBiggerOrEqualValue(start) &
            _db.expenses.date.isSmallerThanValue(end),
      );
    if (excludeCategoryIds != null && excludeCategoryIds.isNotEmpty) {
      query.where(_db.expenses.categoryId.isIn(excludeCategoryIds).not());
    }
    final row = await query.getSingle();
    return Money.fromMinor(row.read(sum) ?? 0);
  }

  /// Date of the single oldest expense across every category, or null when
  /// there are no expenses at all (fresh install). Feeds the recommendation
  /// engine's "how many of the last 6 months are real usage history" check.
  Future<DateTime?> earliestExpenseDate() async {
    final min = _db.expenses.date.min();
    final row = await (_db.selectOnly(
      _db.expenses,
    )..addColumns([min])).getSingle();
    return row.read(min);
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

  /// Live spend per category in [start, end) — same grouping as
  /// [totalsByCategory] but via `.watch()` so budget_setup_screen's
  /// per-category "spent" figure updates on every add/delete, not just on
  /// first load.
  Stream<Map<int, Money>> watchTotalsByCategory(DateTime start, DateTime end) {
    final sum = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.categoryId, sum])
      ..where(
        _db.expenses.date.isBiggerOrEqualValue(start) &
            _db.expenses.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.expenses.categoryId]);
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.expenses.categoryId)!: Money.fromMinor(r.read(sum) ?? 0),
      },
    );
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

/// Raw expense list for a half-open [start, end) range, capped at a row limit,
/// newest first — feeds [AllTransactionsScreen] (no need for the heavier
/// [ReportData] there). The limit grows as the user scrolls (lazy pagination).
/// The 4th key element is the category filter: selected ids sorted and
/// joined with `,` (empty string = no filter) — a plain `String` rather than
/// a `Set`/`List` so the family key has real value equality. The 5th is the
/// raw search box text (empty = no search).
final expensesInRangeProvider =
    StreamProvider.family<
      List<ExpenseRow>,
      (DateTime, DateTime, int, String, String)
    >((ref, key) {
      // Watched, not read: category names feed the search, so a rename has to
      // re-run the query rather than match against a cached list.
      final categories = ref.watch(allCategoriesProvider).value ?? const [];
      return ref
          .watch(expenseRepositoryProvider)
          .watchInRange(
            key.$1,
            key.$2,
            limit: key.$3,
            categoryIds: key.$4.isEmpty
                ? null
                : key.$4.split(',').map(int.parse).toSet(),
            search: parseExpenseQuery(key.$5, categories),
          );
    });

/// Categories with at least one expense in [start, end), sorted for display —
/// feeds the category filter chips on [AllTransactionsScreen].
final categoriesInRangeProvider =
    StreamProvider.family<List<CategoryRow>, (DateTime, DateTime)>((
      ref,
      key,
    ) async* {
      final cats = ref.watch(allCategoriesProvider).value ?? const [];
      final byId = {for (final c in cats) c.id: c};
      await for (final ids
          in ref
              .watch(expenseRepositoryProvider)
              .distinctCategoryIdsInRange(key.$1, key.$2)) {
        final cats = [
          for (final id in ids)
            if (byId[id] != null) byId[id]!,
        ];
        cats.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        yield cats;
      }
    });

final currentMonthExpensesProvider = StreamProvider<List<ExpenseRow>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchMonth(DateTime.now()),
);

final currentMonthTotalProvider = FutureProvider<Money>(
  (ref) => ref.watch(expenseRepositoryProvider).monthTotal(DateTime.now()),
);

/// Live lifetime spend per tag — feeds the Tags report list.
final tagTotalsProvider = StreamProvider<Map<int, Money>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchTotalsByTag(),
);

/// Live expense count for one tag — feeds the Tags report list.
final tagExpenseCountProvider = StreamProvider.family<int, int>(
  (ref, tagId) => ref.watch(expenseRepositoryProvider).watchCountByTag(tagId),
);

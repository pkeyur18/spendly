import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';
import '../expenses/expense_repository.dart';

/// Budget CRUD (FR-23, FR-24), scoped per month via [monthKeyFor]. Overall
/// monthly budget = the row with a null categoryId; per-category budgets have
/// their categoryId set. Budgets table has no unique index, so upserts
/// find-then-write to avoid duplicate rows.
class BudgetRepository {
  BudgetRepository(this._db);
  final AppDatabase _db;

  Stream<List<BudgetRow>> watchAllForMonth(DateTime month) {
    final key = monthKeyFor(month);
    return (_db.select(
      _db.budgets,
    )..where((t) => t.monthKey.equals(key))).watch();
  }

  /// Overall monthly budget = the budgets row with a null categoryId.
  /// Null stream value = no budget set (drives the empty state).
  Stream<Money?> watchOverallBudget(DateTime month) {
    final key = monthKeyFor(month);
    return (_db.select(_db.budgets)
          ..where((t) => t.categoryId.isNull() & t.monthKey.equals(key)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : Money.fromMinor(row.amountMinor));
  }

  Future<void> setOverall(DateTime month, Money amount) =>
      _upsert(null, month, amount);
  Future<void> setForCategory(DateTime month, int categoryId, Money amount) =>
      _upsert(categoryId, month, amount);

  Future<void> clearForCategory(DateTime month, int categoryId) async {
    final key = monthKeyFor(month);
    await (_db.delete(_db.budgets)..where(
          (t) => t.categoryId.equals(categoryId) & t.monthKey.equals(key),
        ))
        .go();
  }

  /// Copies every budget row (overall + per-category) from [fromMonth] onto
  /// [toMonth], overwriting anything already set there — an explicit,
  /// user-triggered action, so clobbering the target month is expected.
  Future<void> carryForward({
    required DateTime fromMonth,
    required DateTime toMonth,
  }) async {
    final rows =
        await (_db.select(_db.budgets)
              ..where((t) => t.monthKey.equals(monthKeyFor(fromMonth))))
            .get();
    for (final row in rows) {
      await _upsert(row.categoryId, toMonth, Money.fromMinor(row.amountMinor));
    }
  }

  /// Insert or update the single budget row for [categoryId] (null = overall)
  /// in [month].
  Future<void> _upsert(int? categoryId, DateTime month, Money amount) async {
    final key = monthKeyFor(month);
    final existing =
        await (_db.select(_db.budgets)..where(
              (t) =>
                  (categoryId == null
                      ? t.categoryId.isNull()
                      : t.categoryId.equals(categoryId)) &
                  t.monthKey.equals(key),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: Value(categoryId),
              amountMinor: amount.minor,
              monthKey: key,
            ),
          );
    } else {
      await (_db.update(_db.budgets)..where((t) => t.id.equals(existing.id)))
          .write(BudgetsCompanion(amountMinor: Value(amount.minor)));
    }
  }
}

/// Which budget thresholds a spend jump newly crossed. Returns the subset of
/// [80, 100] where `before` was under the line and `after` is at/over it —
/// so an alert fires once per real crossing, not on every add. Pure + exact
/// (integer compare, no float). Zero/negative budget = never alerts.
List<int> crossedThresholds(Money before, Money after, Money budget) {
  if (budget.minor <= 0) return const [];
  final out = <int>[];
  for (final t in const [80, 100]) {
    final line = budget.minor * t; // compare against minor * 100
    if (before.minor * 100 < line && after.minor * 100 >= line) out.add(t);
  }
  return out;
}

/// By how much [categoryTotal] exceeds [overall], or null when there's
/// nothing to compare (no overall budget set) or the total isn't over.
Money? categoryBudgetOverrun(Money categoryTotal, Money? overall) {
  if (overall == null || categoryTotal <= overall) return null;
  return categoryTotal - overall;
}

Money _ignoredBudgetSum(Map<int, Money> perCategoryBudgets, Set<int> ignoredIds) =>
    perCategoryBudgets.entries
        .where((e) => ignoredIds.contains(e.key))
        .fold(Money.zero, (a, e) => a + e.value);

/// Overall budget with each ignored-for-budget category's own per-category
/// budget netted out, so the bar/percentage stays meaningful once that
/// category's spend is excluded from the numerator elsewhere. Null stays
/// null. Never negative (clamped at zero if ignored budgets exceed overall).
Money? effectiveOverallBudget(
  Money? overall,
  Map<int, Money> perCategoryBudgets,
  Set<int> ignoredIds,
) {
  if (overall == null) return null;
  final minor =
      overall.minor - _ignoredBudgetSum(perCategoryBudgets, ignoredIds).minor;
  return Money.fromMinor(minor < 0 ? 0 : minor);
}

/// Sum of per-category budgets, excluding categories ignored for budget.
Money effectiveCategoryBudgetTotal(
  Map<int, Money> perCategoryBudgets,
  Set<int> ignoredIds,
) => perCategoryBudgets.entries
    .where((e) => !ignoredIds.contains(e.key))
    .fold(Money.zero, (a, e) => a + e.value);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(databaseProvider)),
);

final overallBudgetForMonthProvider = StreamProvider.family<Money?, String>(
  (ref, monthKey) => ref
      .watch(budgetRepositoryProvider)
      .watchOverallBudget(_monthFromKey(monthKey)),
);

final allBudgetsForMonthProvider = StreamProvider.family<List<BudgetRow>, String>(
  (ref, monthKey) => ref
      .watch(budgetRepositoryProvider)
      .watchAllForMonth(_monthFromKey(monthKey)),
);

/// Per-category budgets as a map (categoryId to amount); overall row excluded.
final perCategoryBudgetsForMonthProvider = Provider.family<Map<int, Money>, String>(
  (ref, monthKey) {
    final rows = ref.watch(allBudgetsForMonthProvider(monthKey)).value ?? const [];
    return {
      for (final r in rows)
        if (r.categoryId != null) r.categoryId!: Money.fromMinor(r.amountMinor),
    };
  },
);

/// Real per-category spend for [monthKey], raw/unfiltered — including
/// categories flagged "ignore for budget", so budget_setup_screen can still
/// show an ignored category's own actual spend even though it's excluded
/// from every aggregate (report total/breakdown/top categories/etc).
final categorySpendForMonthProvider =
    FutureProvider.family<Map<int, Money>, String>((ref, monthKey) {
      final (start, end) = monthBounds(_monthFromKey(monthKey));
      return ref.watch(expenseRepositoryProvider).totalsByCategory(start, end);
    });

/// Convenience wrappers for call sites that only ever care about *now*
/// (Quick Add threshold checks, the home dashboard, category screens) — the
/// budget-setup screen is the only place that needs a specific month.
final overallBudgetProvider = StreamProvider<Money?>(
  (ref) => ref
      .watch(budgetRepositoryProvider)
      .watchOverallBudget(DateTime.now()),
);

final perCategoryBudgetsProvider = Provider<Map<int, Money>>(
  (ref) => ref.watch(perCategoryBudgetsForMonthProvider(monthKeyFor(DateTime.now()))),
);

DateTime _monthFromKey(String monthKey) {
  final parts = monthKey.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
}

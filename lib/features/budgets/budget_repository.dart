import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';

/// Budget CRUD (FR-23, FR-24). Overall monthly budget = the row with a null
/// categoryId; per-category budgets have their categoryId set. Budgets table
/// has no unique index, so upserts find-then-write to avoid duplicate rows.
class BudgetRepository {
  BudgetRepository(this._db);
  final AppDatabase _db;

  Stream<List<BudgetRow>> watchAll() => _db.select(_db.budgets).watch();

  /// Overall monthly budget = the budgets row with a null categoryId.
  /// Null stream value = no budget set (drives the empty state).
  Stream<Money?> watchOverallBudget() {
    return (_db.select(_db.budgets)..where((t) => t.categoryId.isNull()))
        .watchSingleOrNull()
        .map((row) => row == null ? null : Money.fromMinor(row.amountMinor));
  }

  Future<void> setOverall(Money amount) => _upsert(null, amount);
  Future<void> setForCategory(int categoryId, Money amount) =>
      _upsert(categoryId, amount);

  Future<void> clearForCategory(int categoryId) async {
    await (_db.delete(
      _db.budgets,
    )..where((t) => t.categoryId.equals(categoryId))).go();
  }

  /// Insert or update the single budget row for [categoryId] (null = overall).
  Future<void> _upsert(int? categoryId, Money amount) async {
    final existing =
        await (_db.select(_db.budgets)..where(
              (t) => categoryId == null
                  ? t.categoryId.isNull()
                  : t.categoryId.equals(categoryId),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: Value(categoryId),
              amountMinor: amount.minor,
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

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(databaseProvider)),
);

final overallBudgetProvider = StreamProvider<Money?>(
  (ref) => ref.watch(budgetRepositoryProvider).watchOverallBudget(),
);

final allBudgetsProvider = StreamProvider<List<BudgetRow>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchAll(),
);

/// Per-category budgets as a map (categoryId to amount); overall row excluded.
final perCategoryBudgetsProvider = Provider<Map<int, Money>>((ref) {
  final rows = ref.watch(allBudgetsProvider).value ?? const [];
  return {
    for (final r in rows)
      if (r.categoryId != null) r.categoryId!: Money.fromMinor(r.amountMinor),
  };
});

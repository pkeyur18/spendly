import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';

/// Sprint 2 needs only to *read* the overall monthly budget for the hero bar
/// (FR-16). Full budget setup (overall + per-category CRUD) lands in Sprint 3.
class BudgetRepository {
  BudgetRepository(this._db);
  final AppDatabase _db;

  /// Overall monthly budget = the budgets row with a null categoryId.
  /// Null stream value = no budget set (drives the empty state).
  Stream<Money?> watchOverallBudget() {
    return (_db.select(_db.budgets)..where((t) => t.categoryId.isNull()))
        .watchSingleOrNull()
        .map((row) => row == null ? null : Money.fromMinor(row.amountMinor));
  }
}

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(databaseProvider)),
);

final overallBudgetProvider = StreamProvider<Money?>(
  (ref) => ref.watch(budgetRepositoryProvider).watchOverallBudget(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../budgets/budget_repository.dart';
import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';
import '../home/dashboard_providers.dart';
import 'widget_snapshot.dart';

/// Recompute the widget snapshot from current data and push it to the native
/// widgets (FR-29). Called after every write that changes totals: Quick Add
/// save, restore, and app cold-start/resume (the catch-all). Reads one-shot
/// from the repositories so it doesn't depend on a stream having emitted.
Future<void> refreshWidgets(WidgetRef ref) async {
  final expenses = ref.read(expenseRepositoryProvider);
  final now = DateTime.now();

  // Fresh one-shot reads, not the cached categoriesByIdProvider/
  // perCategoryBudgetsProvider — those are Providers built from a Drift
  // stream's cached `.value`, which lags the just-committed write by at
  // least one microtask. A new `.watch()` subscription always re-queries.
  final cats = await ref.read(categoryRepositoryProvider).watchAll().first;
  final ignored = ignoredCategoryIds({for (final c in cats) c.id: c});
  final todayTotal = await expenses.todayTotal(now, ignored);
  final monthTotal = await expenses.monthTotal(now, excludeCategoryIds: ignored);
  final rawBudget = await ref
      .read(budgetRepositoryProvider)
      .watchOverallBudget(now)
      .first;
  final budgetRows = await ref
      .read(budgetRepositoryProvider)
      .watchAllForMonth(now)
      .first;
  final perCategoryBudgets = {
    for (final r in budgetRows)
      if (r.categoryId != null) r.categoryId!: Money.fromMinor(r.amountMinor),
  };
  final budget = effectiveOverallBudget(rawBudget, perCategoryBudgets, ignored);

  // Trend: reuse the same pure bucketing the dashboard uses.
  final lastSix = await expenses.watchLastNMonths(6).first;
  final trend = trendBuckets(lastSix, 6, now);

  // Quick-add: active categories, last-used moved to the front (mirrors Quick
  // Add's own preselection), capped to 4 by the snapshot builder.
  final active = await ref.read(categoryRepositoryProvider).watchActive().first;
  final lastUsedId = ref.read(lastUsedCategoryIdProvider);
  final ordered = [...active];
  if (lastUsedId != null) {
    final i = ordered.indexWhere((c) => c.id == lastUsedId);
    if (i > 0) ordered.insert(0, ordered.removeAt(i));
  }

  final snapshot = buildWidgetSnapshot(
    todayTotal: todayTotal,
    monthTotal: monthTotal,
    budget: budget,
    trend: trend,
    quickAddCategories: ordered,
    now: now,
  );
  await WidgetBridge().write(snapshot);
}

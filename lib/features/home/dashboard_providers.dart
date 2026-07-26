import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';

/// One donut/legend slice: category, its spend, and its fraction of the total.
typedef CategorySlice = (CategoryRow category, Money total, double fraction);

/// One trend bar: month label, that month's spend, whether it's the current month.
typedef TrendBar = (String label, Money total, bool isCurrent);

// ---- Pure derivations (unit-tested without widgets/DB) ----

Money sumMoney(Iterable<ExpenseRow> expenses) =>
    expenses.fold(Money.zero, (acc, e) => acc + e.amount);

/// Spend per category, fraction of grand total, sorted high→low. Skips
/// categories with no matching row (defensive) and zero-total categories.
List<CategorySlice> buildBreakdown(
  List<ExpenseRow> expenses,
  Map<int, CategoryRow> byId,
) {
  final totals = <int, Money>{};
  for (final e in expenses) {
    totals[e.categoryId] = (totals[e.categoryId] ?? Money.zero) + e.amount;
  }
  final grand = sumMoney(expenses);
  final slices = <CategorySlice>[
    for (final entry in totals.entries)
      if (byId[entry.key] != null && entry.value.minor > 0)
        (byId[entry.key]!, entry.value, entry.value.ratioOf(grand)),
  ];
  slices.sort((a, b) => b.$2.minor.compareTo(a.$2.minor));
  return slices;
}

/// Last [n] months up to [now], oldest→newest, each bucketed to its month total.
List<TrendBar> trendBuckets(List<ExpenseRow> expenses, int n, DateTime now) {
  final fmt = DateFormat.MMM();
  final bars = <TrendBar>[];
  for (var i = n - 1; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    final total = sumMoney(
      expenses.where((e) => e.date.year == m.year && e.date.month == m.month),
    );
    bars.add((fmt.format(m), total, i == 0));
  }
  return bars;
}

// ---- Providers (valueOrNull → empty fallback keeps the UI simple) ----

final categoriesByIdProvider = Provider<Map<int, CategoryRow>>((ref) {
  final cats = ref.watch(allCategoriesProvider).value ?? const [];
  return {for (final c in cats) c.id: c};
});

/// Categories flagged "ignore for budget" — excluded from aggregate
/// totals/rankings, not from their own per-category tracking.
Set<int> ignoredCategoryIds(Map<int, CategoryRow> byId) =>
    {for (final c in byId.values) if (c.isIgnoredForBudget) c.id};

final monthTotalProvider = Provider<Money>((ref) {
  final expenses = ref.watch(currentMonthExpensesProvider).value ?? const [];
  final ignored = ignoredCategoryIds(ref.watch(categoriesByIdProvider));
  return sumMoney(expenses.where((e) => !ignored.contains(e.categoryId)));
});

final categoryBreakdownProvider = Provider<List<CategorySlice>>((ref) {
  final expenses = ref.watch(currentMonthExpensesProvider).value ?? const [];
  final byId = ref.watch(categoriesByIdProvider);
  final ignored = ignoredCategoryIds(byId);
  return buildBreakdown(
    expenses.where((e) => !ignored.contains(e.categoryId)).toList(),
    byId,
  );
});

/// Recent transactions (this month, newest first), paired with their category.
final recentExpensesProvider = Provider<List<(ExpenseRow, CategoryRow?)>>((
  ref,
) {
  final expenses = ref.watch(currentMonthExpensesProvider).value ?? const [];
  final byId = ref.watch(categoriesByIdProvider);
  return [for (final e in expenses.take(5)) (e, byId[e.categoryId])];
});

/// Category of the most recent expense — Quick Add preselects it (fallback in
/// the screen = first active category). Null when there are no expenses.
final lastUsedCategoryIdProvider = Provider<int?>((ref) {
  final expenses = ref.watch(currentMonthExpensesProvider).value ?? const [];
  return expenses.isEmpty ? null : expenses.first.categoryId;
});

final _lastSixMonthsProvider = StreamProvider<List<ExpenseRow>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchLastNMonths(6),
);

final trendProvider = Provider<List<TrendBar>>((ref) {
  final expenses = ref.watch(_lastSixMonthsProvider).value ?? const [];
  return trendBuckets(expenses, 6, DateTime.now());
});

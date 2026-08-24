import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../expenses/expense_repository.dart';
import '../expenses/recurring_repository.dart';
import '../home/dashboard_providers.dart' show categoriesByIdProvider;
import 'insight_math.dart';

/// Categories whose current-month spend has moved significantly against
/// their trailing 3-completed-month average. One-shot (`FutureProvider`,
/// not a `StreamProvider`) — insights are a point-in-time read, re-fetched
/// each time the Insights screen opens, not something that needs to update
/// live while it's on screen.
final categoryTrendsProvider = FutureProvider<List<CategoryTrend>>((ref) async {
  final repo = ref.watch(expenseRepositoryProvider);
  final categoriesById = ref.watch(categoriesByIdProvider);
  final now = DateTime.now();
  final (curStart, curEnd) = monthBounds(now);
  final current = await repo.totalsByCategory(curStart, curEnd);

  // Three trailing completed months, zero-filled for a category that had no
  // spend in a given month — skipping that month instead of counting it as
  // zero would inflate the average for anyone who only spent in 1 of 3.
  final priorMonths = <Map<int, Money>>[];
  for (var i = 1; i <= 3; i++) {
    final month = DateTime(now.year, now.month - i, 1);
    final (start, end) = monthBounds(month);
    priorMonths.add(await repo.totalsByCategory(start, end));
  }

  final categoryIds = <int>{...current.keys, for (final m in priorMonths) ...m.keys};
  final trends = <CategoryTrend>[];
  for (final categoryId in categoryIds) {
    final category = categoriesById[categoryId];
    if (category == null) continue; // archived/deleted since — nothing to name it
    final priorSumMinor = priorMonths.fold(
      0,
      (sum, m) => sum + (m[categoryId]?.minor ?? 0),
    );
    trends.add(
      CategoryTrend(
        categoryName: category.name,
        current: current[categoryId] ?? Money.zero,
        priorAverage: Money.fromMinor(priorSumMinor ~/ priorMonths.length),
      ),
    );
  }
  return significantCategoryTrends(trends);
});

/// Monthly-equivalent total of every active recurring expense — see
/// `monthlySubscriptionsTotal`'s doc comment for the cadence normalization.
final subscriptionsTotalProvider = FutureProvider<Money>((ref) async {
  final templates = await ref
      .watch(recurringRepositoryProvider)
      .watchTemplates()
      .first;
  return monthlySubscriptionsTotal(templates);
});

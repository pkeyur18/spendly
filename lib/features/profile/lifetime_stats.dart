import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expense_repository.dart';

/// Profile's lifetime usage stats (FR-51): months tracked, total expenses
/// logged, and distinct categories actually used.
class LifetimeStats {
  const LifetimeStats({
    required this.monthsTracked,
    required this.expensesLogged,
    required this.categoriesUsed,
  });

  static const zero = LifetimeStats(
    monthsTracked: 0,
    expensesLogged: 0,
    categoriesUsed: 0,
  );

  final int monthsTracked;
  final int expensesLogged;
  final int categoriesUsed;
}

/// Pure: distinct (year, month) pairs, total row count, distinct categoryId
/// count — unit-tested independently of the DB.
LifetimeStats computeLifetimeStats(List<(DateTime, int)> rows) {
  if (rows.isEmpty) return LifetimeStats.zero;
  final months = <String>{};
  final categories = <int>{};
  for (final (date, categoryId) in rows) {
    months.add('${date.year}-${date.month}');
    categories.add(categoryId);
  }
  return LifetimeStats(
    monthsTracked: months.length,
    expensesLogged: rows.length,
    categoriesUsed: categories.length,
  );
}

final lifetimeStatsProvider = StreamProvider<LifetimeStats>((ref) {
  return ref
      .watch(expenseRepositoryProvider)
      .watchLifetimeStats()
      .map(computeLifetimeStats);
});

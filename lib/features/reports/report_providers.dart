import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../expenses/expense_repository.dart';
import '../home/dashboard_providers.dart';
import 'report_model.dart';

/// Half-open [start, end) range — the family key for a report.
typedef DateRange = (DateTime start, DateTime end);

/// A report over any date range (FR-19). One in-range fetch derives total,
/// count, breakdown, top-5 and weekly trend; a second fetch gets the previous
/// period's total for the comparison line.
final reportProvider = StreamProvider.family<ReportData, DateRange>((
  ref,
  range,
) {
  final (start, end) = range;
  final repo = ref.watch(expenseRepositoryProvider);
  final categoriesById = ref.watch(categoriesByIdProvider);
  final (pStart, pEnd) = previousPeriod(start, end);
  return repo.watchInRange(start, end).asyncMap((expenses) async {
    final previousTotal = await repo.totalInRange(
      pStart,
      pEnd,
      excludeCategoryIds: ignoredCategoryIds(categoriesById),
    );
    return buildReport(
      start: start,
      end: end,
      expenses: expenses,
      previousTotal: previousTotal,
      categoriesById: categoriesById,
    );
  });
});

/// Lifetime report for one tag/trip (FR — trip expense tracking): all
/// expenses carrying [tagId], spanning their own min/max date rather than a
/// fixed window. No previous-period comparison — a trip has no "last month".
final tagReportProvider = StreamProvider.family<ReportData, int>((ref, tagId) {
  final repo = ref.watch(expenseRepositoryProvider);
  final categoriesById = ref.watch(categoriesByIdProvider);
  return repo.watchByTag(tagId).map((expenses) {
    final now = DateTime.now();
    final start = expenses.isEmpty
        ? now
        : expenses.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final end =
        (expenses.isEmpty
                ? now
                : expenses
                      .map((e) => e.date)
                      .reduce((a, b) => a.isAfter(b) ? a : b))
            .add(const Duration(days: 1));
    return buildReport(
      start: start,
      end: end,
      expenses: expenses,
      previousTotal: Money.zero,
      categoriesById: categoriesById,
    );
  });
});

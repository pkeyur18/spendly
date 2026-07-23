import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final previousTotal = await repo.totalInRange(pStart, pEnd);
    return buildReport(
      start: start,
      end: end,
      expenses: expenses,
      previousTotal: previousTotal,
      categoriesById: categoriesById,
    );
  });
});

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../home/dashboard_providers.dart'
    show CategorySlice, TrendBar, ignoredCategoryIds, sumMoney;

/// Everything a report screen renders (FR-20). Built purely from a list of
/// in-range expenses + the previous period's total — no DB, so it's unit-tested
/// at the function level (per the no-pumpAndSettle gotcha).
class ReportData {
  const ReportData({
    required this.start,
    required this.end,
    required this.expenses,
    required this.total,
    required this.previousTotal,
    required this.changePct,
    required this.txnCount,
    required this.dailyAverage,
    required this.topCategory,
    required this.breakdown,
    required this.ignoredBreakdown,
    required this.ignoredTotal,
    required this.top5,
    required this.weekly,
  });

  final DateTime start;
  final DateTime end; // half-open
  final List<ExpenseRow> expenses; // full in-range list (Excel export, FR-32)
  final Money total;
  final Money previousTotal;

  /// Percent change vs the previous same-length period. Null when the previous
  /// period spent nothing (can't divide by zero).
  final double? changePct;
  final int txnCount;
  final Money dailyAverage;

  /// Highest-spend category slice, or null when the range is empty.
  final CategorySlice? topCategory;
  final List<CategorySlice> breakdown; // desc by spend

  /// Spend in categories flagged "ignore for budget" — excluded from [total]
  /// and [breakdown] above, but reported separately (FR-32 export).
  final List<CategorySlice> ignoredBreakdown; // desc by spend
  final Money ignoredTotal;
  final List<ExpenseRow> top5; // biggest single expenses, desc
  final List<TrendBar> weekly; // W1..Wn buckets (custom range trend)

  bool get isEmpty => txnCount == 0;
  bool get changeUp => (changePct ?? 0) >= 0;
}

/// Per-category totals over [expenses] → slices (fraction of [groupTotal]), desc.
List<CategorySlice> _breakdown(
  List<ExpenseRow> expenses,
  Map<int, CategoryRow> categoriesById,
  Money groupTotal,
) {
  final byCategory = <int, Money>{};
  for (final e in expenses) {
    byCategory[e.categoryId] =
        (byCategory[e.categoryId] ?? Money.zero) + e.amount;
  }
  return <CategorySlice>[
    for (final entry in byCategory.entries)
      if (categoriesById[entry.key] != null && entry.value.minor > 0)
        (
          categoriesById[entry.key]!,
          entry.value,
          entry.value.ratioOf(groupTotal),
        ),
  ]..sort((a, b) => b.$2.minor.compareTo(a.$2.minor));
}

/// Build a report over [start, end) from its expenses. [previousTotal] is the
/// same-length preceding window's total (caller fetches it). Pure.
ReportData buildReport({
  required DateTime start,
  required DateTime end,
  required List<ExpenseRow> expenses,
  required Money previousTotal,
  required Map<int, CategoryRow> categoriesById,
}) {
  // Categories flagged "ignore for budget" are excluded from every aggregate
  // below, but [expenses] itself stays the full raw list (Excel export/FR-32).
  final ignored = ignoredCategoryIds(categoriesById);
  final counted = expenses
      .where((e) => !ignored.contains(e.categoryId))
      .toList();

  final total = sumMoney(counted);
  final breakdown = _breakdown(counted, categoriesById, total);

  final ignoredExpenses = expenses
      .where((e) => ignored.contains(e.categoryId))
      .toList();
  final ignoredTotal = sumMoney(ignoredExpenses);
  final ignoredBreakdown = _breakdown(
    ignoredExpenses,
    categoriesById,
    ignoredTotal,
  );

  // Top 5 single expenses by amount, desc.
  final top5 = [...counted]
    ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

  // Daily average over the inclusive day span (>= 1 to avoid /0).
  final days = end.difference(start).inDays;
  final dailyAverage = Money.fromMinor(total.minor ~/ (days < 1 ? 1 : days));

  final changePct = previousTotal.minor == 0
      ? null
      : (total.minor - previousTotal.minor) / previousTotal.minor * 100;

  return ReportData(
    start: start,
    end: end,
    expenses: expenses,
    total: total,
    previousTotal: previousTotal,
    changePct: changePct,
    txnCount: counted.length,
    dailyAverage: dailyAverage,
    topCategory: breakdown.isEmpty ? null : breakdown.first,
    breakdown: breakdown,
    ignoredBreakdown: ignoredBreakdown,
    ignoredTotal: ignoredTotal,
    top5: top5.take(5).toList(),
    weekly: weeklyBuckets(counted, start, end),
  );
}

/// Bucket in-range expenses into 7-day windows labelled W1..Wn (custom-range
/// trend). The most recent bucket is flagged current (highlighted like the
/// prototype's `.bar.active`).
List<TrendBar> weeklyBuckets(
  List<ExpenseRow> expenses,
  DateTime start,
  DateTime end,
) {
  final days = end.difference(start).inDays;
  final n = ((days <= 0 ? 1 : days) / 7).ceil().clamp(1, 12);
  final totals = List<Money>.filled(n, Money.zero);
  for (final e in expenses) {
    final offset = e.date.difference(start).inDays;
    if (offset < 0) continue;
    final i = (offset ~/ 7).clamp(0, n - 1);
    totals[i] = totals[i] + e.amount;
  }
  return [for (var i = 0; i < n; i++) ('W${i + 1}', totals[i], i == n - 1)];
}

/// Same-length window immediately before [start, end) — the comparison period.
(DateTime, DateTime) previousPeriod(DateTime start, DateTime end) {
  final span = end.difference(start);
  return (start.subtract(span), start);
}

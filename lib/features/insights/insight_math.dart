import '../../core/db/database.dart';
import '../../core/money/money.dart';

/// One category's current-month spend against its trailing average — the
/// raw material for `significantCategoryTrends`. Pure data, no formatting.
class CategoryTrend {
  const CategoryTrend({
    required this.categoryName,
    required this.current,
    required this.priorAverage,
  });

  final String categoryName;
  final Money current;

  /// Average spend in this category over the trailing window (e.g. the
  /// prior 3 completed months). Zero if the category had no spend in that
  /// window at all — see [percentChange]'s null case for why that's treated
  /// as "nothing to compare against" rather than "infinite increase".
  final Money priorAverage;

  /// Percent change of [current] vs [priorAverage], rounded. Null when
  /// [priorAverage] is zero — a brand-new category has no baseline to be
  /// "up 400%" against, and reporting one would be noise, not insight.
  int? get percentChange {
    if (priorAverage.minor <= 0) return null;
    return ((current.minor - priorAverage.minor) * 100 / priorAverage.minor)
        .round();
  }
}

/// Categories whose current-month spend moved by at least [thresholdPercent]
/// against their trailing average, sorted by the size of that move
/// (largest first). [minCurrentMinor] filters out a category too small for
/// a percentage swing to mean anything (₹10 → ₹20 is "up 100%" and also
/// nothing worth telling anyone about).
List<CategoryTrend> significantCategoryTrends(
  List<CategoryTrend> trends, {
  int thresholdPercent = 30,
  int minCurrentMinor = 50000, // ₹500
}) {
  final flagged = trends.where((t) {
    final pct = t.percentChange;
    if (pct == null) return false;
    if (t.current.minor < minCurrentMinor) return false;
    return pct.abs() >= thresholdPercent;
  }).toList();
  flagged.sort(
    (a, b) => b.percentChange!.abs().compareTo(a.percentChange!.abs()),
  );
  return flagged;
}

/// Monthly-equivalent total of every active recurring expense template —
/// "₹3,200/month in subscriptions". Daily/weekly cadences are normalized by
/// the average number of those periods per calendar month (365/12 days,
/// 365/12/7 weeks) rather than a flat ×30 or ×4, so the figure doesn't drift
/// depending on which month it happens to be computed in.
Money monthlySubscriptionsTotal(List<ExpenseRow> recurringTemplates) {
  var totalMinor = 0.0;
  for (final e in recurringTemplates) {
    final periodsPerMonth = switch (e.recurrence) {
      Recurrence.daily => 365.0 / 12,
      Recurrence.weekly => 365.0 / 12 / 7,
      Recurrence.monthly || null => 1.0,
    };
    totalMinor += e.amountMinor * periodsPerMonth;
  }
  return Money.fromMinor(totalMinor.round());
}

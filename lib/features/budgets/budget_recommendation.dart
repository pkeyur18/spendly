import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';

/// One category's recommended next-month budget, and how many of the last 6
/// calendar months actually fall within the user's usage history (the rest
/// predate their first-ever expense, so aren't real zero-spend data).
class BudgetRecommendation {
  const BudgetRecommendation({required this.amount, required this.monthsUsed});
  final Money amount;
  final int monthsUsed;
}

/// Buckets [expenses] into the 6 calendar months immediately before [now]'s
/// month (oldest -> newest; [now]'s own in-progress month is never
/// included), per category, with trip-tagged expenses excluded. [expenses]
/// is expected to already be scoped to that 6-month window - this function
/// only buckets and filters, it doesn't fetch.
List<Map<int, Money>> monthlyCategoryTotals(
  List<ExpenseRow> expenses,
  Set<int> tripTagIds,
  DateTime now,
) {
  final counted = expenses.where(
    (e) => e.tagId == null || !tripTagIds.contains(e.tagId),
  );
  final buckets = <Map<int, Money>>[];
  for (var i = 6; i >= 1; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    final totals = <int, Money>{};
    for (final e in counted) {
      if (e.date.year == m.year && e.date.month == m.month) {
        totals[e.categoryId] = (totals[e.categoryId] ?? Money.zero) + e.amount;
      }
    }
    buckets.add(totals);
  }
  return buckets;
}

/// How many of the 6 window months fall on/after [earliestExpenseMonth] -
/// the rest predate the user's first-ever expense. 0 when there's no
/// expense history at all.
int monthsUsedInWindow(DateTime? earliestExpenseMonth, DateTime now) {
  if (earliestExpenseMonth == null) return 0;
  final earliestMonthStart = DateTime(
    earliestExpenseMonth.year,
    earliestExpenseMonth.month,
    1,
  );
  var count = 0;
  for (var i = 6; i >= 1; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    if (!m.isBefore(earliestMonthStart)) count++;
  }
  return count;
}

/// Recommended next-month budget for one category, from its monthly totals
/// (oldest -> newest, already trimmed to real history by the caller — see
/// `budgetRecommendationsProvider`; a month with no spend is a real 0, not
/// missing). Weighted average favouring recent months; the single month
/// exceeding 1.75x the median is dropped first (only once there are >= 4
/// months, so a small sample can't be gutted by outlier removal). Rounded to
/// the nearest ₹50. Null when every month is zero (no history at all).
Money? recommendCategoryBudget(List<Money> monthlyTotals) {
  if (monthlyTotals.every((m) => m.minor == 0)) return null;

  var totals = monthlyTotals;
  if (totals.length >= 4) {
    final sorted = [...totals]..sort((a, b) => a.minor.compareTo(b.minor));
    final median = sorted[sorted.length ~/ 2];
    Money? worstOutlier;
    if (median.minor > 0) {
      for (final m in totals) {
        if (m.minor > median.minor * 175 ~/ 100) {
          if (worstOutlier == null || m.minor > worstOutlier.minor) {
            worstOutlier = m;
          }
        }
      }
    }
    if (worstOutlier != null) {
      totals = [...totals]..removeAt(totals.indexOf(worstOutlier));
    }
  }

  var weightedSum = 0;
  var weightTotal = 0;
  for (var i = 0; i < totals.length; i++) {
    final weight = i + 1; // oldest = 1 .. newest = totals.length
    weightedSum += totals[i].minor * weight;
    weightTotal += weight;
  }
  final average = weightedSum ~/ weightTotal;
  const roundToMinor = 5000; // nearest ₹50
  final rounded =
      ((average + roundToMinor ~/ 2) ~/ roundToMinor) * roundToMinor;
  return Money.fromMinor(rounded);
}

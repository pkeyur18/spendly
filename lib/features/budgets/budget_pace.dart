import '../../core/money/money.dart';

/// Where this month's spending sits against the pace the budget implies.
///
/// Deliberately three states, not two: "over budget" and "spending too fast
/// but still inside the budget" call for different reactions, and collapsing
/// them hides the second until it is too late to act on.
enum PaceStatus {
  /// At or under the spend the elapsed part of the month would justify.
  onTrack,

  /// Past that spend, but the budget still has room.
  overPace,

  /// The budget is gone.
  overBudget,
}

/// A month's budget translated into "what can I spend today".
///
/// The dashboard already showed a month total and a percentage of budget, but
/// a percentage can't be acted on without also knowing how much month is left
/// — 61% is a problem on day 12 and a win on day 25. Every field here exists
/// to turn that percentage into a decision.
class BudgetPace {
  const BudgetPace({
    required this.perDayLeft,
    required this.daysLeft,
    required this.expectedByNow,
    required this.overspend,
    required this.status,
  });

  /// Budget remaining divided across the days remaining, today included.
  /// Floors at zero — a blown budget yields no allowance, never a negative one.
  final Money perDayLeft;

  /// Days remaining in the month, today included, so this is never 0.
  final int daysLeft;

  /// What an even spend rate would have spent by the end of today.
  final Money expectedByNow;

  /// How far past the budget the month has gone; zero while still inside it.
  final Money overspend;

  final PaceStatus status;
}

/// Pace for the calendar month containing [now]. Null when there is no usable
/// budget — matching the dashboard's existing "budget.minor > 0" gate, since a
/// zero budget is not a budget and cannot be paced against.
///
/// [spent] is expected to already exclude "ignored for budget" categories; the
/// caller owns that filtering (see `effectiveOverallBudget`).
BudgetPace? budgetPace({
  required Money spent,
  required Money? budget,
  required DateTime now,
}) {
  if (budget == null || budget.minor <= 0) return null;

  // Day 0 of the following month == last day of this one.
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final daysLeft = daysInMonth - now.day + 1;

  // Integer math throughout — money never touches a double. Truncating (not
  // rounding) the per-day figure keeps daysLeft × perDayLeft at or under what
  // is actually left, so following the advice can't overshoot the budget.
  final expectedByNow = Money.fromMinor(
    budget.minor * now.day ~/ daysInMonth,
  );
  final remaining = budget.minor - spent.minor;
  final perDayLeft = Money.fromMinor(remaining <= 0 ? 0 : remaining ~/ daysLeft);

  return BudgetPace(
    perDayLeft: perDayLeft,
    daysLeft: daysLeft,
    expectedByNow: expectedByNow,
    overspend: Money.fromMinor(remaining < 0 ? -remaining : 0),
    status: spent >= budget
        ? PaceStatus.overBudget
        : spent > expectedByNow
        ? PaceStatus.overPace
        : PaceStatus.onTrack,
  );
}

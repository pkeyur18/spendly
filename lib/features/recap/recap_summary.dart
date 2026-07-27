import '../../core/money/money.dart';

/// Pure recap math result — see [computeRecapSummary].
class RecapSummary {
  const RecapSummary({
    required this.hasBudget,
    required this.isPositive,
    required this.savings,
    required this.percentUsed,
  });

  final bool hasBudget;

  /// True when [savings] is zero or positive (break-even counts as a win).
  final bool isPositive;

  /// budget - total. Null when [hasBudget] is false.
  final Money? savings;

  /// (total / budget * 100).round(). Null when [hasBudget] is false.
  final int? percentUsed;
}

/// Pure recap math, extracted from the widget so it's unit-testable without
/// pumping (same pattern as `report_model.dart`'s `buildReport`). `hasBudget`
/// mirrors `_HeroCard`'s own gate (`budget != null && budget.minor > 0`,
/// `home_screen.dart`) so a zero-amount budget row reads the same as "no
/// budget set" everywhere in the app.
RecapSummary computeRecapSummary({required Money total, required Money? budget}) {
  final hasBudget = budget != null && budget.minor > 0;
  if (!hasBudget) {
    return const RecapSummary(
      hasBudget: false,
      isPositive: false,
      savings: null,
      percentUsed: null,
    );
  }
  final savings = budget - total;
  return RecapSummary(
    hasBudget: true,
    isPositive: savings.minor >= 0,
    savings: savings,
    percentUsed: (total.ratioOf(budget) * 100).round(),
  );
}

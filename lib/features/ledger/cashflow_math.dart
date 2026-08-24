import '../../core/money/money.dart';

/// Net cashflow and savings rate for a period. Pure so it's unit-testable
/// without a database, same pattern as `recap_summary.dart`.
class CashflowSummary {
  const CashflowSummary({required this.net, required this.savingsRatePercent});

  /// income - expense. Can be negative (spent more than came in).
  final Money net;

  /// (net / income * 100).round(), or null when [income] was zero — "kept
  /// 22%" is meaningless with nothing to divide by.
  final int? savingsRatePercent;
}

CashflowSummary computeCashflow({required Money income, required Money expense}) {
  final net = income - expense;
  if (income.minor <= 0) {
    return CashflowSummary(net: net, savingsRatePercent: null);
  }
  return CashflowSummary(
    net: net,
    savingsRatePercent: (net.minor * 100 / income.minor).round(),
  );
}

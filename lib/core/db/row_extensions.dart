import 'dart:ui';

import '../money/money.dart';
import 'database.dart';

/// Bridge Drift rows to domain types without duplicating them into parallel
/// model classes (ponytail: getters, not new classes).

extension ExpenseRowX on ExpenseRow {
  /// Decimal-safe amount, always in home currency. Storage is `amountMinor`
  /// (int); never expose a float.
  Money get amount => Money.fromMinor(amountMinor);

  /// What was actually paid abroad, or null for a home-currency expense.
  /// Display only — [amount] is what every total is built from.
  Money? get fxAmount =>
      fxAmountMinor == null ? null : Money.fromMinor(fxAmountMinor!);

  /// True when this expense carries a foreign receipt worth showing.
  bool get isForeign => fxCurrency != null && fxAmountMinor != null;
}

extension TagRowX on TagRow {
  /// True when this tag is a trip abroad — expenses under it are entered in
  /// [fxCurrency] and converted on save.
  bool get isTravel => fxCurrency != null && fxRateMicros != null;
}

extension CategoryRowX on CategoryRow {
  Color get color => Color(colorValue);
}

/// 'YYYY-MM' stamp for the month [d] falls in — the unit opening balances
/// reset by, and the format [Accounts.openingBalanceMonth] stores.
String yearMonthStamp(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

extension LedgerEntryRowX on LedgerEntryRow {
  Money get amount => Money.fromMinor(amountMinor);
}

extension SavingsGoalRowX on SavingsGoalRow {
  Money get target => Money.fromMinor(targetMinor);
  Money get saved => Money.fromMinor(savedMinor);

  /// 0.0–1.0, never over 100% even once the goal is exceeded — a progress
  /// bar has nowhere to put the overflow. [isComplete] is the un-clamped
  /// signal for that case.
  double get progressRatio =>
      targetMinor <= 0 ? 0 : (savedMinor / targetMinor).clamp(0, 1);

  bool get isComplete => targetMinor > 0 && savedMinor >= targetMinor;
}

extension AccountRowX on AccountRow {
  Money get openingBalance => Money.fromMinor(openingBalanceMinor);

  /// The opening balance as it should actually be shown right now: the
  /// stored value if it was set this month, zero otherwise. Opening balance
  /// resets every month on the 1st — the user re-enters it, nothing here
  /// zeroes the DB row itself, so a month that's already rolled over just
  /// reads as zero until they do.
  Money effectiveOpeningBalance(DateTime now) =>
      openingBalanceMonth == yearMonthStamp(now) ? openingBalance : Money.zero;
}

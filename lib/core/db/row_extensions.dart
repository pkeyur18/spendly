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

import 'dart:ui';

import '../money/money.dart';
import 'database.dart';

/// Bridge Drift rows to domain types without duplicating them into parallel
/// model classes (ponytail: getters, not new classes).

extension ExpenseRowX on ExpenseRow {
  /// Decimal-safe amount. Storage is `amountMinor` (int); never expose a float.
  Money get amount => Money.fromMinor(amountMinor);
}

extension CategoryRowX on CategoryRow {
  Color get color => Color(colorValue);
}

import '../../core/money/money.dart';

/// An account's running balance: opening balance plus every income, expense,
/// and transfer ever recorded against it — it carries forward, never resets.
/// Never stored: always recomputed, matching the app's existing preference
/// for computed over persisted state.
Money computeAccountBalance({
  required Money openingBalance,
  required Money income,
  required Money expense,
  required Money transfersIn,
  required Money transfersOut,
}) => openingBalance + income - expense + transfersIn - transfersOut;

import '../../core/money/money.dart';

/// An account's derived balance for one window (the current month, matching
/// [AccountRow.effectiveOpeningBalance]'s own monthly-reset scope — there is
/// no lifetime balance in this app, only "this month's" one). Never stored:
/// always recomputed from opening balance plus this window's activity,
/// matching the app's existing preference for computed over persisted state.
Money computeAccountBalance({
  required Money openingBalance,
  required Money income,
  required Money expense,
  required Money transfersIn,
  required Money transfersOut,
}) => openingBalance + income - expense + transfersIn - transfersOut;

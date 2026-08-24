import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../accounts/account_repository.dart';
import '../expenses/expense_repository.dart' show monthBounds;
import 'balance_math.dart';
import 'ledger_repository.dart';

/// This month's derived balance for every account (`balance_math.dart` —
/// scoped to the current month, matching [AccountRow.effectiveOpeningBalance]'s
/// own monthly reset). Computed from four independently-reactive maps, never
/// stored — each term updates its own provider as its underlying data
/// changes, and this just recombines them.
final accountBalancesThisMonthProvider = Provider<Map<int, Money>>((ref) {
  final now = DateTime.now();
  final range = monthBounds(now);
  final accounts = ref.watch(allAccountsProvider).value ?? const [];
  final expense = ref.watch(accountTotalsByRangeProvider(range)).value ?? const {};
  final income =
      ref.watch(incomeTotalsByAccountRangeProvider(range)).value ?? const {};
  final transfersIn =
      ref.watch(transfersInTotalsByAccountRangeProvider(range)).value ??
      const {};
  final transfersOut =
      ref.watch(transfersOutTotalsByAccountRangeProvider(range)).value ??
      const {};
  return {
    for (final a in accounts)
      a.id: computeAccountBalance(
        openingBalance: a.effectiveOpeningBalance(now),
        income: income[a.id] ?? Money.zero,
        expense: expense[a.id] ?? Money.zero,
        transfersIn: transfersIn[a.id] ?? Money.zero,
        transfersOut: transfersOut[a.id] ?? Money.zero,
      ),
  };
});

/// Sum of every active account's balance — the dashboard summary figure.
/// Archived accounts are excluded, same convention as every other
/// account-total shown in the app: they're hidden from every picker, so
/// folding their balance into a headline total would count money the user
/// can no longer act on through the UI.
final totalBalanceThisMonthProvider = Provider<Money>((ref) {
  final active = ref.watch(activeAccountsProvider).value ?? const [];
  final balances = ref.watch(accountBalancesThisMonthProvider);
  return active.fold(
    Money.zero,
    (sum, a) => sum + (balances[a.id] ?? Money.zero),
  );
});

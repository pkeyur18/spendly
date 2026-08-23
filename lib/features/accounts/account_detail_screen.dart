import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../expenses/all_transactions_screen.dart' show groupExpensesByDay;
import '../expenses/expense_repository.dart';
import '../expenses/widgets/expense_tile.dart';
import '../home/dashboard_providers.dart' show categoriesByIdProvider;
import 'account_repository.dart';
import 'accounts_screen.dart' show showAccountEditSheet;

/// All-time bounds for "every expense ever paid from this account", day-
/// truncated rather than a raw `DateTime.now()`. A fresh `DateTime.now()`
/// evaluated inside a provider key caused a real bug once already (search
/// got permanently stuck reloading — see `transactionsQueryKey`'s doc
/// comment): a `StreamProvider.family` key compared by value gets a new,
/// never-before-seen key on nearly every rebuild if it carries a
/// microsecond-precision timestamp, so Riverpod never lets the query survive
/// long enough to emit. Day precision is stable for a whole session and
/// loses nothing — no expense can be dated in the future.
(DateTime, DateTime) _allTimeRange(DateTime now) => (
  DateTime(2000),
  DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
);

const _pageSize = 100;

/// Every expense paid from one account, all-time, with a running lifetime
/// total. Reached by tapping an account in [AccountsScreen] (edit moved to
/// an app-bar action here, since "see the account" is the more common intent
/// behind a tap than "edit the account").
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.account});
  final AccountRow account;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  int _limit = _pageSize;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 400) return;
    // staleness-ok: reads the same page build() already watches, for pagination bookkeeping.
    final loaded = ref
        .read(_accountExpensesProvider((widget.account.id, _limit)))
        .asData
        ?.value
        .length;
    if (loaded != null && loaded >= _limit) {
      setState(() => _limit += _pageSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final key = (widget.account.id, _limit);
    final async = ref.watch(_accountExpensesProvider(key));
    final range = _allTimeRange(DateTime.now());
    final total = ref
        .watch(accountTotalsByRangeProvider(range))
        .value?[widget.account.id];
    final byId = ref.watch(categoriesByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account.name),
        actions: [
          IconButton(
            tooltip: 'Edit account',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await showAccountEditSheet(
                context,
                existing: widget.account,
              );
              // The sheet may have archived this account (setArchived pops
              // with the id too) — leave the detail screen either way, since
              // there is nothing useful left to show for an archived one.
              if (result != null && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total spent',
                    style: TextStyle(fontSize: 13, color: palette.textDim),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (total ?? Money.zero).format(locale: 'en_IN'),
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.account.openingBalanceMinor != 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Opening balance '
                      '${Money.fromMinor(widget.account.openingBalanceMinor).format(locale: 'en_IN')}',
                      style: TextStyle(fontSize: 12, color: palette.textDim),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                message: "Couldn't load transactions.",
                onRetry: () => ref.invalidate(_accountExpensesProvider(key)),
              ),
              data: (expenses) {
                if (expenses.isEmpty) {
                  return const EmptyView(
                    icon: Icons.receipt_long_outlined,
                    message: 'No transactions from this account yet.',
                  );
                }
                final items = <Object>[];
                final dayTotals = <DateTime, Money>{};
                for (final entry in groupExpensesByDay(expenses).entries) {
                  items.add(entry.key);
                  items.addAll(entry.value);
                  dayTotals[entry.key] = entry.value.fold(
                    Money.zero,
                    (sum, e) => sum + e.amount,
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item is DateTime) {
                      return DayGroupHeader(item, total: dayTotals[item]!);
                    }
                    final e = item as ExpenseRow;
                    return ExpenseTile(
                      expense: e,
                      category: byId[e.categoryId],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Paginated, all-time expense list for one account — the same shape as
/// [expensesInRangeProvider] but keyed by account instead of date range,
/// since an account detail screen has no range to scope to.
final _accountExpensesProvider =
    StreamProvider.family<List<ExpenseRow>, (int, int)>((ref, key) {
      final (accountId, limit) = key;
      final range = _allTimeRange(DateTime.now());
      return ref
          .watch(expenseRepositoryProvider)
          .watchInRange(
            range.$1,
            range.$2,
            limit: limit,
            accountIds: {accountId},
          );
    });

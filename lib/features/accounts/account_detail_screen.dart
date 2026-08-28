import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../expenses/expense_repository.dart';
import '../expenses/widgets/expense_tile.dart';
import '../home/dashboard_providers.dart' show categoriesByIdProvider;
import '../ledger/account_balance_provider.dart';
import '../ledger/income_screen.dart' show showIncomeEditSheet;
import '../ledger/ledger_repository.dart';
import '../ledger/transfer_screen.dart' show showTransferEditSheet;
import 'account_repository.dart';
import 'accounts_screen.dart' show showAccountEditSheet;

const _pageSize = 100;

/// Every expense paid from one account, plus every ledger entry (income,
/// transfer) touching it, unioned into one timeline — the one screen in the
/// app where `Expenses` and `LedgerEntries` are ever combined (Phase 6; see
/// the "separate ledger table" decision in
/// `docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md`). Reached by
/// tapping an account in [AccountsScreen] (edit moved to an app-bar action
/// here, since "see the account" is the more common intent behind a tap
/// than "edit the account").
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.account});
  final AccountRow account;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  int _limit = _pageSize;
  bool _fullYear = false;
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

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    return _fullYear ? yearToDateBounds(now) : monthBounds(now);
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 400) return;
    // staleness-ok: reads the same page build() already watches, for pagination bookkeeping.
    final loaded = ref
        .read(_accountExpensesProvider((widget.account.id, _limit, _range)))
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
    final range = _range;
    final expenseKey = (widget.account.id, _limit, range);
    final expensesAsync = ref.watch(_accountExpensesProvider(expenseKey));
    final ledgerAsync = ref.watch(
      _accountLedgerProvider((widget.account.id, range)),
    );
    final total = ref
        .watch(accountTotalsByRangeProvider(range))
        .value?[widget.account.id];
    final byId = ref.watch(categoriesByIdProvider);
    final accountById = ref.watch(accountsByIdProvider);
    // Reads through the live provider so a save from the edit sheet below
    // reflects immediately without leaving this screen — widget.account is
    // just the snapshot passed in at navigation time.
    final account = accountById[widget.account.id] ?? widget.account;
    final openingBalance = account.openingBalance;
    final balance = ref.watch(accountBalancesProvider)[widget.account.id] ?? Money.zero;
    // A liability account still in debt reads "You owe ₹X" (magnitude, red)
    // rather than a bare negative "Balance" — paid off or overpaid, there's
    // no debt left to call out, so it falls back to a normal balance.
    final inDebt = account.isLiability && balance.minor < 0;
    final activeAccounts =
        ref.watch(activeAccountsProvider).value ?? const <AccountRow>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _fullYear = !_fullYear;
              _limit = _pageSize;
            }),
            child: Text(_fullYear ? 'This month' : 'Full year'),
          ),
          if (activeAccounts.length > 1)
            IconButton(
              tooltip: 'Transfer money',
              icon: const Icon(Icons.send_rounded),
              onPressed: () => showTransferEditSheet(
                context,
                defaultFromAccountId: widget.account.id,
              ),
            ),
          IconButton(
            tooltip: 'Edit account',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await showAccountEditSheet(
                context,
                existing: account,
              );
              // A plain save stays right here, reading updated values off
              // the live provider watch below. Archiving leaves — there is
              // nothing useful left to show for an archived account.
              if (result != null && result.archived && context.mounted) {
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
            child: Row(
              children: [
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inDebt ? 'You owe' : 'Balance',
                          style: TextStyle(fontSize: 13, color: palette.textDim),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (inDebt ? balance.abs() : balance).format(
                            locale: 'en_IN',
                          ),
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: inDebt ? AppColors.red : AppColors.primary,
                          ),
                        ),
                        if (openingBalance.minor != 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Opening ${openingBalance.format(locale: 'en_IN')}',
                            style: TextStyle(fontSize: 11, color: palette.textDim),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullYear ? 'Spent this year' : 'Spent this month',
                          style: TextStyle(fontSize: 13, color: palette.textDim),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (total ?? Money.zero).format(locale: 'en_IN'),
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: expensesAsync.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                message: "Couldn't load transactions.",
                onRetry: () =>
                    ref.invalidate(_accountExpensesProvider(expenseKey)),
              ),
              data: (expenses) {
                final ledger = ledgerAsync.value ?? const <LedgerEntryRow>[];
                if (expenses.isEmpty && ledger.isEmpty) {
                  return const EmptyView(
                    icon: Icons.receipt_long_outlined,
                    message: 'No activity on this account yet.',
                  );
                }
                final groups = _groupTimelineByDay(expenses, ledger);
                final items = <Object>[];
                final dayTotals = <DateTime, Money>{};
                for (final entry in groups.entries) {
                  items.add(entry.key);
                  items.addAll(entry.value);
                  dayTotals[entry.key] = entry.value
                      .whereType<ExpenseRow>()
                      .fold(Money.zero, (sum, e) => sum + e.amount);
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
                    if (item is ExpenseRow) {
                      return ExpenseTile(
                        expense: item,
                        category: byId[item.categoryId],
                      );
                    }
                    return _LedgerTimelineTile(
                      entry: item as LedgerEntryRow,
                      thisAccountId: widget.account.id,
                      accountById: accountById,
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

/// One income or transfer row in the unioned account timeline. Read-only
/// here (tap to edit) — delete lives in the edit sheet or, for income, the
/// Income screen's own swipe gesture.
class _LedgerTimelineTile extends StatelessWidget {
  const _LedgerTimelineTile({
    required this.entry,
    required this.thisAccountId,
    required this.accountById,
  });

  final LedgerEntryRow entry;
  final int thisAccountId;
  final Map<int, AccountRow> accountById;

  bool get _isIncome => entry.kind == LedgerEntryKind.income;
  bool get _isTransferOut => entry.kind == LedgerEntryKind.transfer &&
      entry.accountId == thisAccountId;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final (icon, title, sign, color) = switch ((_isIncome, _isTransferOut)) {
      (true, _) => (
          Icons.savings_outlined,
          entry.sourceLabel?.isNotEmpty == true ? entry.sourceLabel! : 'Income',
          '+',
          AppColors.primary,
        ),
      (false, true) => (
          Icons.call_made,
          'Transfer to '
              '${accountById[entry.counterAccountId]?.name ?? 'another account'}',
          '-',
          Theme.of(context).colorScheme.onSurface,
        ),
      (false, false) => (
          Icons.call_received,
          'Transfer from '
              '${accountById[entry.accountId]?.name ?? 'another account'}',
          '+',
          AppColors.primary,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => _isIncome
            ? showIncomeEditSheet(context, existing: entry)
            : showTransferEditSheet(context, existing: entry),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.icon),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    relativeDayLabel(entry.date),
                    style: TextStyle(fontSize: 12, color: palette.textDim),
                  ),
                ],
              ),
            ),
            Text(
              '$sign${entry.amount.format(locale: 'en_IN')}',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Merges expenses and ledger entries into day buckets, both already
/// date-desc from their own queries — a plain merge-sort by date, then
/// bucketed the same way `groupExpensesByDay` already does for expenses
/// alone.
Map<DateTime, List<Object>> _groupTimelineByDay(
  List<ExpenseRow> expenses,
  List<LedgerEntryRow> ledger,
) {
  final combined = <Object>[...expenses, ...ledger]
    ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
  final groups = <DateTime, List<Object>>{};
  for (final item in combined) {
    final d = _dateOf(item);
    final day = DateTime(d.year, d.month, d.day);
    groups.putIfAbsent(day, () => []).add(item);
  }
  return groups;
}

DateTime _dateOf(Object o) =>
    o is ExpenseRow ? o.date : (o as LedgerEntryRow).date;

/// Paginated expense list for one account, scoped to the current month or
/// year-to-date per the screen's toggle.
final _accountExpensesProvider =
    StreamProvider.family<List<ExpenseRow>, (int, int, (DateTime, DateTime))>(
      (ref, key) {
        final (accountId, limit, range) = key;
        return ref
            .watch(expenseRepositoryProvider)
            .watchInRange(
              range.$1,
              range.$2,
              limit: limit,
              accountIds: {accountId},
            );
      },
    );

/// Every ledger entry touching one account within a range — unpaginated,
/// since income + transfers per account per month/year are naturally few
/// compared to expenses.
final _accountLedgerProvider =
    StreamProvider.family<List<LedgerEntryRow>, (int, (DateTime, DateTime))>(
      (ref, key) {
        final (accountId, range) = key;
        return ref
            .watch(ledgerRepositoryProvider)
            .watchTouchingAccount(accountId, range.$1, range.$2);
      },
    );

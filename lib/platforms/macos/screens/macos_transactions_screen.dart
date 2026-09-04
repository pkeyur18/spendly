import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/database.dart';
import '../../../core/db/row_extensions.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_glyph.dart';
import '../../../features/accounts/account_repository.dart';
import '../../../features/categories/category_repository.dart' show allCategoriesProvider;
import '../../../features/expenses/all_transactions_screen.dart' show groupExpensesByDay, transactionsQueryKey;
import '../../../features/expenses/expense_repository.dart';
import '../../../features/home/dashboard_providers.dart' show categoriesByIdProvider;
import '../../../features/expenses/widgets/expense_tile.dart' show DayGroupHeader;
import '../widgets/macos_expense_row.dart';

/// Master-detail transactions browser — read only, so unlike the mobile
/// `AllTransactionsScreen` there's no swipe-to-delete, tap-to-edit, or Quick
/// Add link; selecting a row just shows its detail in the right pane.
///
/// Queries the whole synced history at once (limit 1000) rather than the
/// mobile screen's lazy month-window pagination — a Sync import is a fixed
/// snapshot, not a live, ever-growing local ledger, so there's no cold-start
/// cost to page around.
class MacosTransactionsScreen extends ConsumerStatefulWidget {
  const MacosTransactionsScreen({super.key});

  @override
  ConsumerState<MacosTransactionsScreen> createState() => _MacosTransactionsScreenState();
}

class _MacosTransactionsScreenState extends ConsumerState<MacosTransactionsScreen> {
  int? _selectedCategoryId;
  int? _selectedExpenseId;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final key = transactionsQueryKey(
      searching: false,
      search: _search,
      range: (DateTime(2000), DateTime(now.year, now.month, now.day).add(const Duration(days: 1))),
      limit: 1000,
      categoryKey: _selectedCategoryId == null ? '' : '$_selectedCategoryId',
      now: now,
    );
    final expenses = ref.watch(expensesInRangeProvider(key)).value ?? const [];
    final byId = ref.watch(categoriesByIdProvider);
    final accountsById = ref.watch(accountsByIdProvider);
    final categories = ref.watch(allCategoriesProvider).value ?? const [];

    final selected = _selectedExpenseId == null
        ? null
        : expenses.cast<ExpenseRow?>().firstWhere((e) => e?.id == _selectedExpenseId, orElse: () => null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Search transactions…',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(label: 'All', selected: _selectedCategoryId == null, onTap: () => setState(() => _selectedCategoryId = null)),
                for (final c in categories) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: c.name,
                    selected: _selectedCategoryId == c.id,
                    onTap: () => setState(() => _selectedCategoryId = c.id),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: expenses.isEmpty
                      ? Center(
                          child: Text(
                            'No transactions${_selectedCategoryId != null || _search.isNotEmpty ? ' match this filter' : ' yet — sync from your iPhone first'}.',
                            style: TextStyle(color: Theme.of(context).extension<AppPalette>()!.textDim),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final entry in groupExpensesByDay(expenses).entries) ...[
                              DayGroupHeader(
                                entry.key,
                                total: entry.value.fold(entry.value.first.amount * 0, (s, e) => s + e.amount),
                              ),
                              for (final e in entry.value)
                                MacosExpenseRow(
                                  expense: e,
                                  category: byId[e.categoryId],
                                  selected: e.id == _selectedExpenseId,
                                  onTap: () => setState(() => _selectedExpenseId = e.id),
                                ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: 320,
                  child: selected == null
                      ? const _EmptyDetail()
                      : _DetailPane(expense: selected, category: byId[selected.categoryId], account: accountsById[selected.accountId]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Material(
      color: selected ? AppColors.primary : palette.card,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: selected ? AppColors.primary : palette.line),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : palette.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return AppCard(
      child: Center(
        child: Text('Select a transaction', style: TextStyle(color: palette.textDim, fontSize: 12.5)),
      ),
    );
  }
}

class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.expense, required this.category, required this.account});
  final ExpenseRow expense;
  final CategoryRow? category;
  final AccountRow? account;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (category?.color ?? palette.textDim).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                alignment: Alignment.center,
                child: CategoryGlyph(category?.icon ?? '💸', size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.note?.isNotEmpty == true ? expense.note! : (category?.name ?? 'Expense'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    Text(category?.name ?? 'Uncategorized', style: TextStyle(fontSize: 11.5, color: palette.textDim)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '-${expense.amount.format(locale: 'en_IN')}',
            style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 26),
          ),
          const Divider(height: 24),
          _DetailRow('Account', account?.name ?? '—'),
          _DetailRow('Date', DateFormat.yMMMd().add_jm().format(expense.date)),
          _DetailRow('Note', expense.note?.isNotEmpty == true ? expense.note! : '—'),
          _DetailRow('Payment method', expense.paymentMethod ?? '—'),
          if (expense.isForeign) _DetailRow('Paid abroad', expense.fxAmount!.formatAs(expense.fxCurrency!)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 13, color: palette.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'To edit or delete, use Spendly on your iPhone',
                  style: TextStyle(fontSize: 11, color: palette.textDim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: palette.textDim)),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

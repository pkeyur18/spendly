import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/database.dart';
import '../../../core/db/row_extensions.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../expense_repository.dart';
import '../quick_add_screen.dart';

/// "Today"/"Yesterday"/calendar-date label for a day, used both for
/// [ExpenseTile]'s per-row timestamp and day-group headers.
String relativeDayLabel(DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat.MMMd().format(d);
}

/// Day-group header ("Today"/"Yesterday"/calendar date) above a bucket of
/// [ExpenseTile]s, with that day's total in a tinted pill on the right.
/// Shared by [AllTransactionsScreen] and the custom report.
class DayGroupHeader extends StatelessWidget {
  const DayGroupHeader(this.day, {required this.total, super.key});

  final DateTime day;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            relativeDayLabel(day),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.textDim,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              total.format(locale: 'en_IN'),
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One expense row: category icon, title, relative time, amount. Tap to edit,
/// swipe to delete with confirmation. Shared by the Home "Recent" list and
/// [AllTransactionsScreen].
class ExpenseTile extends ConsumerWidget {
  const ExpenseTile({super.key, required this.expense, required this.category});

  final ExpenseRow expense;
  final CategoryRow? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final title = expense.note?.isNotEmpty == true
        ? expense.note!
        : (category?.name ?? 'Expense');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Dismissible(
        key: ValueKey(expense.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (_) => showDialog<bool>(
          context: context,
          builder: (dialogContext) => Theme(
            data: AppTheme.boldDialogActions(dialogContext),
            child: AlertDialog(
              title: const Text('Delete expense?'),
              content: const Text('This can\'t be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ),
        ).then((confirmed) => confirmed ?? false),
        onDismissed: (_) =>
            ref.read(expenseRepositoryProvider).delete(expense.id),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => QuickAddScreen(editing: expense)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (category?.color ?? palette.textDim).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                alignment: Alignment.center,
                child: Text(
                  category?.icon ?? '💸',
                  style: const TextStyle(fontSize: 17),
                ),
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
                      '${relativeDayLabel(expense.date)} · ${DateFormat.jm().format(expense.date)}',
                      style: TextStyle(fontSize: 12, color: palette.textDim),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '-${expense.amount.format(locale: 'en_IN')}',
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  // What was actually paid abroad. Only rendered when there
                  // is one — a domestic row keeps its single-line layout,
                  // no placeholder.
                  if (expense.isForeign)
                    Text(
                      expense.fxAmount!.formatAs(expense.fxCurrency!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

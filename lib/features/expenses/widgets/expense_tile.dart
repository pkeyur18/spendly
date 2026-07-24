import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/database.dart';
import '../../../core/db/row_extensions.dart';
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
          builder: (dialogContext) => AlertDialog(
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
              Text(
                '-${expense.amount.format(locale: 'en_IN')}',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

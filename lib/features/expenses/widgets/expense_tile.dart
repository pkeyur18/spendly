import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/database.dart';
import '../../../core/db/row_extensions.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/glass.dart';
import '../expense_repository.dart';
import '../quick_add_screen.dart';
import '../receipt_repository.dart';

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
/// swipe or long-press to delete (with a 5-second undo either way), long-press
/// to add the same expense again. Shared by the Home "Recent" list and
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
        // No confirm dialog: the swipe is already deliberate, and a dialog on
        // every delete taxes the common case to guard the rare one. Undo
        // inverts that — one tap on the frequent path, and the mistake is
        // actually recoverable instead of merely warned about.
        onDismissed: (_) => _deleteWithUndo(context, ref, title),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          onTap: () => openQuickAddScreen(context, editing: expense),
          longPressHint: 'Show actions for this expense',
          onLongPress: () {
            HapticFeedback.selectionClick();
            _showActions(context, ref, title);
          },
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Existence only, never the bytes — this list can be
                        // 100 rows deep, and loading every photo just to show
                        // a dot would be the exact cost the receipt table was
                        // split out from `expenses` to avoid.
                        if (ref
                            .watch(expenseIdsWithReceiptProvider)
                            .value
                            ?.contains(expense.id) ??
                            false) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 13,
                            color: palette.textDim,
                          ),
                        ],
                      ],
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

  /// Deletes now, offers 5 seconds to take it back. Shared by the swipe and
  /// the actions sheet so there is exactly one delete path, and it is always
  /// the undoable one.
  void _deleteWithUndo(BuildContext context, WidgetRef ref, String title) {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(expenseRepositoryProvider);
    repo.delete(expense.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "$title"'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restore(expense),
          ),
        ),
      );
  }

  /// Long-press menu. Exists for discoverability — a long-press that jumped
  /// straight into a copy worked, but nothing on screen ever taught that the
  /// gesture was there. Listing the actions makes the gesture self-teaching
  /// the first time it's found by accident.
  ///
  /// It also gives Delete a path that isn't a swipe, which matters for anyone
  /// who can't reliably perform a drag gesture — until now the only way to
  /// delete an expense was [Dismissible].
  void _showActions(BuildContext context, WidgetRef ref, String title) {
    showGlassSheet<void>(
      context,
      builder: (sheetContext) {
        final palette = Theme.of(sheetContext).extension<AppPalette>()!;
        void close() => Navigator.of(sheetContext).pop();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: palette.textDim),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Add again'),
                subtitle: const Text('Same amount and category, dated today'),
                onTap: () {
                  close();
                  openQuickAddScreen(context, duplicateOf: expense);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  close();
                  openQuickAddScreen(context, editing: expense);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.red),
                ),
                onTap: () {
                  close();
                  _deleteWithUndo(context, ref, title);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

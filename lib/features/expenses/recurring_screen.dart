import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/category_glyph.dart';
import '../home/dashboard_providers.dart';
import '../ledger/income_screen.dart' show showIncomeEditSheet, showIncomeConfirmSheet;
import '../ledger/ledger_repository.dart';
import 'quick_add_screen.dart';
import 'recurring_repository.dart';
import 'recurring_schedule.dart';

/// Recurring expenses and income: what is waiting to be confirmed, and
/// everything scheduled (FR-7; income added schema v21).
///
/// Confirming is always a user action — the app never logs an occurrence on
/// its own (the locked PRD decision, for both kinds). Missed occurrences are
/// not collapsed into one: three unconfirmed weeks really were three
/// payments, so each gets its own confirm-or-skip decision.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recurring'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Expenses'), Tab(text: 'Income')],
          ),
        ),
        body: const TabBarView(
          children: [_ExpenseRecurringTab(), _IncomeRecurringTab()],
        ),
      ),
    );
  }
}

class _ExpenseRecurringTab extends ConsumerWidget {
  const _ExpenseRecurringTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recurringSeriesProvider);
    final byId = ref.watch(categoriesByIdProvider);

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: "Couldn't load recurring expenses.",
        onRetry: () => ref.invalidate(recurringSeriesProvider),
      ),
      data: (series) {
        if (series.isEmpty) {
          return const EmptyView(
            icon: Icons.repeat_rounded,
            message:
                'Nothing repeats yet. Set "Repeat" on an expense to track '
                'rent, EMIs or subscriptions.',
          );
        }
        final due = [
          for (final s in series)
            if (s.pending.isNotEmpty) s,
        ]..sort((a, b) => a.pending.first.compareTo(b.pending.first));
        final scheduled = [
          for (final s in series)
            if (s.pending.isEmpty) s,
        ];

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (due.isNotEmpty) ...[
              const SectionTitle('Waiting for you'),
              for (final s in due)
                _DueCard(series: s, category: byId[s.template.categoryId]),
            ],
            if (scheduled.isNotEmpty) ...[
              const SectionTitle('Scheduled'),
              for (final s in scheduled)
                _ScheduledTile(
                  template: s.template,
                  category: byId[s.template.categoryId],
                ),
            ],
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }
}

/// Income's twin of [_ExpenseRecurringTab]. One real behavioral difference:
/// confirming always opens a reviewable, prefilled sheet
/// (`showIncomeConfirmSheet`) rather than logging in one silent tap — see
/// `LedgerRepository.confirmIncome`'s doc comment for why.
class _IncomeRecurringTab extends ConsumerWidget {
  const _IncomeRecurringTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incomeRecurringSeriesProvider);

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: "Couldn't load recurring income.",
        onRetry: () => ref.invalidate(incomeRecurringSeriesProvider),
      ),
      data: (series) {
        if (series.isEmpty) {
          return const EmptyView(
            icon: Icons.repeat_rounded,
            message:
                'Nothing repeats yet. Set "Repeat" on an income entry to '
                'track salary, meal card reloads or other regular deposits.',
          );
        }
        final due = [
          for (final s in series)
            if (s.pending.isNotEmpty) s,
        ]..sort((a, b) => a.pending.first.compareTo(b.pending.first));
        final scheduled = [
          for (final s in series)
            if (s.pending.isEmpty) s,
        ];

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (due.isNotEmpty) ...[
              const SectionTitle('Waiting for you'),
              for (final s in due) _IncomeDueCard(series: s),
            ],
            if (scheduled.isNotEmpty) ...[
              const SectionTitle('Scheduled'),
              for (final s in scheduled)
                _IncomeScheduledTile(template: s.template),
            ],
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }
}

String _dueLabel(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// One series with occurrences waiting. Only the oldest is actionable: the
/// series is tracked by a single pointer, so resolving them out of order would
/// mean silently swallowing the ones skipped over. The rest are listed so the
/// size of the backlog is visible.
class _DueCard extends ConsumerWidget {
  const _DueCard({required this.series, required this.category});

  final RecurringSeries series;
  final CategoryRow? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final template = series.template;
    final oldest = series.pending.first;
    final rest = series.pending.skip(1).toList();
    final repo = ref.read(recurringRepositoryProvider);
    final title = template.note?.isNotEmpty == true
        ? template.note!
        : (category?.name ?? 'Expense');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryGlyph(category?.icon ?? '🔁', size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Due ${_dueLabel(oldest)}',
                        style: TextStyle(fontSize: 12, color: palette.textDim),
                      ),
                    ],
                  ),
                ),
                Text(
                  template.amount.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                rest.length == 1
                    ? 'Then ${_dueLabel(rest.single)}'
                    : 'Then ${rest.map(_dueLabel).join(', ')}',
                style: TextStyle(fontSize: 12, color: palette.textDim),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => repo.confirm(template, oldest),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      rest.isEmpty ? 'Log it' : 'Log ${_dueLabel(oldest)}',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () => repo.skip(template, oldest),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduledTile extends ConsumerWidget {
  const _ScheduledTile({required this.template, required this.category});

  final ExpenseRow template;
  final CategoryRow? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final title = template.note?.isNotEmpty == true
        ? template.note!
        : (category?.name ?? 'Expense');
    final next = template.nextDueDate;
    final frequency = template.recurrence == null
        ? ''
        : recurrenceLabel(template.recurrence!);
    final ends = template.recurrenceEndDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => openQuickAddScreen(context, editing: template),
        child: Row(
          children: [
            CategoryGlyph(category?.icon ?? '🔁', size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      frequency,
                      // A pre-v10 row can be flagged recurring with nothing
                      // scheduled; say so rather than showing a blank date.
                      if (next != null)
                        'next ${_dueLabel(next)}'
                      else
                        'not scheduled — tap to set it',
                      if (ends != null) 'ends ${_dueLabel(ends)}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: palette.textDim),
                  ),
                ],
              ),
            ),
            Text(
              template.amount.format(locale: 'en_IN'),
              style: const TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              tooltip: 'Stop repeating',
              icon: const Icon(Icons.repeat_on_rounded),
              onPressed: () => _confirmCancel(context, ref, title),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Stop repeating?'),
          content: Text(
            '"$title" will stop reminding you. The expense you already '
            'logged stays in your history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
    if (stop ?? false) {
      await ref.read(recurringRepositoryProvider).cancel(template);
    }
  }
}

/// Income's twin of [_DueCard]. Confirm opens the reviewable, prefilled
/// sheet instead of logging in one tap; Skip stays a direct one-tap action,
/// same as expenses — only confirming needed the extra review step.
class _IncomeDueCard extends ConsumerWidget {
  const _IncomeDueCard({required this.series});

  final IncomeRecurringSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final template = series.template;
    final oldest = series.pending.first;
    final rest = series.pending.skip(1).toList();
    final repo = ref.read(ledgerRepositoryProvider);
    final title = template.sourceLabel?.isNotEmpty == true
        ? template.sourceLabel!
        : 'Income';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.savings_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Due ${_dueLabel(oldest)}',
                        style: TextStyle(fontSize: 12, color: palette.textDim),
                      ),
                    ],
                  ),
                ),
                Text(
                  template.amount.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                rest.length == 1
                    ? 'Then ${_dueLabel(rest.single)}'
                    : 'Then ${rest.map(_dueLabel).join(', ')}',
                style: TextStyle(fontSize: 12, color: palette.textDim),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showIncomeConfirmSheet(
                      context,
                      template: template,
                      occurrence: oldest,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      rest.isEmpty ? 'Confirm' : 'Confirm ${_dueLabel(oldest)}',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () => repo.skipIncome(template, oldest),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeScheduledTile extends ConsumerWidget {
  const _IncomeScheduledTile({required this.template});

  final LedgerEntryRow template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final title = template.sourceLabel?.isNotEmpty == true
        ? template.sourceLabel!
        : 'Income';
    final next = template.nextDueDate;
    final frequency = template.recurrence == null
        ? ''
        : recurrenceLabel(template.recurrence!);
    final ends = template.recurrenceEndDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => showIncomeEditSheet(context, existing: template),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.icon),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.savings_outlined,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      frequency,
                      if (next != null)
                        'next ${_dueLabel(next)}'
                      else
                        'not scheduled — tap to set it',
                      if (ends != null) 'ends ${_dueLabel(ends)}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: palette.textDim),
                  ),
                ],
              ),
            ),
            Text(
              template.amount.format(locale: 'en_IN'),
              style: const TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            IconButton(
              tooltip: 'Stop repeating',
              icon: const Icon(Icons.repeat_on_rounded),
              onPressed: () => _confirmCancel(context, ref, title),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Stop repeating?'),
          content: Text(
            '"$title" will stop reminding you. The income you already '
            'logged stays in your history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
    if (stop ?? false) {
      await ref.read(ledgerRepositoryProvider).cancelIncomeRecurrence(template);
    }
  }
}

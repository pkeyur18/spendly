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
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(60),
            child: _PillTabBar(),
          ),
        ),
        body: const TabBarView(
          children: [_ExpenseRecurringTab(), _IncomeRecurringTab()],
        ),
      ),
    );
  }
}

/// A rounded segmented-control look built on the stock [TabBar] — its
/// indicator becomes the active pill rather than an underline — so swipe
/// sync, accessibility and [DefaultTabController] wiring stay exactly what
/// [TabBar] already provides; only the paint changes.
class _PillTabBar extends StatelessWidget {
  const _PillTabBar();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.line,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: TabBar(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          labelColor: Theme.of(context).textTheme.bodyLarge?.color,
          unselectedLabelColor: palette.textDim,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          tabs: const [Tab(text: 'Expenses'), Tab(text: 'Income')],
        ),
      ),
    );
  }
}

/// Section header for this screen only — uppercase, letter-spaced, muted.
/// A local widget rather than reskinning the shared [SectionTitle] (used
/// across many other screens with its own look).
class _RecurringSectionLabel extends StatelessWidget {
  const _RecurringSectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: palette.textDim,
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
              const _RecurringSectionLabel('Waiting for you'),
              for (final s in due)
                _DueCard(series: s, category: byId[s.template.categoryId]),
            ],
            if (scheduled.isNotEmpty) ...[
              const _RecurringSectionLabel('Scheduled'),
              _ScheduledList(
                tiles: [
                  for (final s in scheduled)
                    _ScheduledTile(
                      template: s.template,
                      category: byId[s.template.categoryId],
                    ),
                ],
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
              const _RecurringSectionLabel('Waiting for you'),
              for (final s in due) _IncomeDueCard(series: s),
            ],
            if (scheduled.isNotEmpty) ...[
              const _RecurringSectionLabel('Scheduled'),
              _ScheduledList(
                tiles: [
                  for (final s in scheduled)
                    _IncomeScheduledTile(template: s.template),
                ],
              ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Due ${_dueLabel(oldest)}',
                        style: TextStyle(fontSize: 12.5, color: palette.textDim),
                      ),
                    ],
                  ),
                ),
                Text(
                  template.amount.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
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
            const SizedBox(height: AppSpacing.md),
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

    return InkWell(
      onTap: () => openQuickAddScreen(context, editing: template),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RecurringAvatar(child: CategoryGlyph(category?.icon ?? '🔁', size: 19)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  template.amount.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: _RecurringAvatar.size + AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: palette.textDim),
                    ),
                  ),
                  _StopRepeatButton(onTap: () => _confirmCancel(context, ref, title)),
                ],
              ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Due ${_dueLabel(oldest)}',
                        style: TextStyle(fontSize: 12.5, color: palette.textDim),
                      ),
                    ],
                  ),
                ),
                Text(
                  template.amount.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
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
            const SizedBox(height: AppSpacing.md),
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

    return InkWell(
      onTap: () => showIncomeEditSheet(context, existing: template),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _RecurringAvatar(
                  child: Icon(Icons.savings_outlined, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  template.amount.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: _RecurringAvatar.size + AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        frequency,
                        if (next != null)
                          'next ${_dueLabel(next)}'
                        else
                          'not scheduled — tap to set it',
                        if (ends != null) 'ends ${_dueLabel(ends)}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: palette.textDim),
                    ),
                  ),
                  if (next != null)
                    _MarkReceivedEarlyButton(
                      onTap: () => showIncomeConfirmSheet(
                        context,
                        template: template,
                        occurrence: next,
                      ),
                    ),
                  _StopRepeatButton(onTap: () => _confirmCancel(context, ref, title)),
                ],
              ),
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

/// Ends a scheduled series. Shared by expense and income tiles — same icon,
/// same tint, same tap target — so the two never drift into different looks.
class _StopRepeatButton extends StatelessWidget {
  const _StopRepeatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return IconButton(
      tooltip: 'Stop repeating',
      onPressed: onTap,
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: palette.textDim.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.icon),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.event_repeat_rounded,
          size: 16,
          color: palette.textDim,
        ),
      ),
    );
  }
}

/// Confirms an income series' next occurrence before its scheduled date —
/// salary landing a few days early shouldn't have to wait for "due" to log
/// it. Income-only: an expense's "next due" is a bill still owed, not
/// something that can arrive ahead of schedule.
class _MarkReceivedEarlyButton extends StatelessWidget {
  const _MarkReceivedEarlyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Mark received early',
      onPressed: onTap,
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.icon),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.event_available_rounded,
          size: 16,
          color: AppColors.green,
        ),
      ),
    );
  }
}

/// Circular icon avatar for a scheduled row — shared shape/size for expense
/// and income tiles so the divided list reads as one consistent pattern.
class _RecurringAvatar extends StatelessWidget {
  const _RecurringAvatar({required this.child});

  final Widget child;

  /// Exposed so a tile's second line can indent past the avatar exactly,
  /// rather than a magic number drifting out of sync with this widget.
  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: palette.card2, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// A card housing every scheduled series as one flat, divider-separated
/// list, rather than one [AppCard] per row.
class _ScheduledList extends StatelessWidget {
  const _ScheduledList({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i != tiles.length - 1)
              Divider(
                height: 1,
                indent: AppSpacing.md,
                endIndent: AppSpacing.md,
                color: palette.line,
              ),
          ],
        ],
      ),
    );
  }
}

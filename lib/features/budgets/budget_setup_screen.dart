import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/glass.dart';
import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';
import '../home/dashboard_providers.dart';
import '../reports/report_providers.dart';
import 'budget_recommendation.dart';
import 'budget_repository.dart';

/// Budget Setup (FR-23,24) — prototype phone 6. Overall + per-category budgets,
/// scoped per month with prev/next navigation and a manual carry-forward
/// action; each card shows a read-only usage bar (spent / budget) coloured by
/// state.
class BudgetSetupScreen extends ConsumerStatefulWidget {
  const BudgetSetupScreen({super.key, this.initialMonth});

  /// Month to open on. Null (the default, every existing call site) opens on
  /// the current calendar month, same as before this param existed.
  final DateTime? initialMonth;

  @override
  ConsumerState<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends ConsumerState<BudgetSetupScreen> {
  late DateTime _month = widget.initialMonth != null
      ? DateTime(widget.initialMonth!.year, widget.initialMonth!.month, 1)
      : DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _stepMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  bool _isNextRealMonth() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1, 1);
    return _month.year == next.year && _month.month == next.month;
  }

  @override
  Widget build(BuildContext context) {
    final monthKey = monthKeyFor(_month);
    final overallAsync = ref.watch(overallBudgetForMonthProvider(monthKey));
    final activeAsync = ref.watch(activeCategoriesProvider);
    final isNextRealMonth = _isNextRealMonth();
    final (recommendedByCategory, recommendedOverall) = isNextRealMonth
        ? ref.watch(budgetRecommendationsProvider)
        : (const <int, BudgetRecommendation>{}, null);

    Widget body;
    if (overallAsync.isLoading || activeAsync.isLoading) {
      body = const LoadingView();
    } else if (overallAsync.hasError || activeAsync.hasError) {
      body = ErrorView(
        message: 'Couldn\'t load budgets.',
        onRetry: () {
          ref.invalidate(overallBudgetForMonthProvider(monthKey));
          ref.invalidate(activeCategoriesProvider);
        },
      );
    } else {
      final overall = overallAsync.value;
      final perCategory = ref.watch(
        perCategoryBudgetsForMonthProvider(monthKey),
      );
      final catsById = ref.watch(categoriesByIdProvider);
      final report = ref.watch(reportProvider(monthBounds(_month))).value;
      final monthTotal = report?.total ?? Money.zero;
      // Raw per-category spend, unfiltered — so an ignored category still
      // shows its own real spent-vs-budget number even though it's dropped
      // from monthTotal/report above.
      final spentByCat =
          ref.watch(categorySpendForMonthProvider(monthKey)).value ??
          const <int, Money>{};
      // Ignored categories' own budget allocation is netted out of both the
      // overall target and the per-category sum, so the bars/percentages
      // stay meaningful once their spend is excluded from the numerator.
      final ignoredIds = ignoredCategoryIds(catsById);
      final effectiveOverall = effectiveOverallBudget(
        overall,
        perCategory,
        ignoredIds,
      );
      final categoryTotal = effectiveCategoryBudgetTotal(
        perCategory,
        ignoredIds,
      );

      // Active categories that don't yet have a budget → the "+ add" picker.
      final active = activeAsync.value ?? const [];
      final budgetable = active
          .where((c) => !perCategory.containsKey(c.id))
          .toList();

      final isEmpty = overall == null && perCategory.isEmpty;

      body = ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          40,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: OutlinedButton(
              onPressed: () => _carryForward(context, ref, isEmpty),
              child: Text(
                'Carry forward from ${DateFormat('MMMM').format(DateTime(_month.year, _month.month - 1, 1))}',
              ),
            ),
          ),
          _BudgetCard(
            title: 'Overall monthly budget',
            spent: monthTotal,
            budget: effectiveOverall,
            onTap: () => _editOverall(context, ref, overall),
            suggestion: recommendedOverall,
            onApplySuggestion: recommendedOverall == null
                ? null
                : () => ref
                      .read(budgetRepositoryProvider)
                      .setOverall(_month, recommendedOverall),
          ),
          if (perCategory.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _CategoryTotalCard(total: categoryTotal, overall: effectiveOverall),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Per category', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (perCategory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No per-category budgets set yet.',
                style: TextStyle(
                  color: Theme.of(context).extension<AppPalette>()!.textDim,
                  fontSize: 13,
                ),
              ),
            ),
          for (final entry in perCategory.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _BudgetCard(
                title:
                    '${catsById[entry.key]?.icon ?? ''} ${catsById[entry.key]?.name ?? 'Category'}'
                        .trim(),
                spent: spentByCat[entry.key] ?? Money.zero,
                budget: entry.value,
                onTap: () =>
                    _editCategory(context, ref, entry.key, entry.value),
                onDelete: () => _deleteCategoryBudget(
                  context,
                  ref,
                  entry.key,
                  catsById[entry.key]?.name ?? 'Category',
                ),
                isIgnored: catsById[entry.key]?.isIgnoredForBudget ?? false,
                onToggleIgnored: (v) async {
                  await ref
                      .read(categoryRepositoryProvider)
                      .setIgnoredForBudget(entry.key, v);
                },
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (isNextRealMonth)
            for (final c in budgetable)
              if (recommendedByCategory[c.id] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SuggestedCategoryRow(
                    category: c,
                    recommendation: recommendedByCategory[c.id]!,
                    onApply: () => ref
                        .read(budgetRepositoryProvider)
                        .setForCategory(
                          _month,
                          c.id,
                          recommendedByCategory[c.id]!.amount,
                        ),
                  ),
                ),
          _AddBudgetButton(
            enabled: budgetable.isNotEmpty,
            onTap: () => _addCategoryBudget(context, ref, budgetable),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('MMMM yyyy').format(_month)),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _stepMonth(-1),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _stepMonth(1),
          ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _carryForward(
    BuildContext context,
    WidgetRef ref,
    bool isEmpty,
  ) async {
    if (!isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Theme(
          data: AppTheme.boldDialogActions(dialogContext),
          child: AlertDialog(
            title: const Text('Overwrite this month\'s budgets?'),
            content: const Text(
              'Carrying forward replaces the overall budget and every '
              'category budget already set for this month with last '
              'month\'s values.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Overwrite'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }
    final prevMonth = DateTime(_month.year, _month.month - 1, 1);
    await ref
        .read(budgetRepositoryProvider)
        .carryForward(fromMonth: prevMonth, toMonth: _month);
  }

  Future<void> _editOverall(
    BuildContext context,
    WidgetRef ref,
    Money? current,
  ) async {
    final amount = await showAmountSheet(
      context,
      initial: current,
      title: 'Overall monthly budget',
    );
    if (amount != null && amount.minor > 0) {
      await ref.read(budgetRepositoryProvider).setOverall(_month, amount);
    }
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref,
    int categoryId,
    Money current,
  ) async {
    final amount = await showAmountSheet(
      context,
      initial: current,
      title: 'Category budget',
    );
    if (amount == null || !context.mounted) return;
    final repo = ref.read(budgetRepositoryProvider);
    if (amount.minor > 0) {
      await repo.setForCategory(_month, categoryId, amount);
      return;
    }
    // Zero clears an existing budget (FR-24) — confirm first, since typing
    // "0" while reconsidering an amount shouldn't silently delete it.
    if (current.minor > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Theme(
          data: AppTheme.boldDialogActions(dialogContext),
          child: AlertDialog(
            title: const Text('Clear this budget?'),
            content: const Text(
              'Setting the amount to zero removes the budget for this month.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep budget'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }
    await repo.clearForCategory(_month, categoryId);
  }

  Future<void> _deleteCategoryBudget(
    BuildContext context,
    WidgetRef ref,
    int categoryId,
    String categoryName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Delete budget?'),
          content: Text("Removes $categoryName's budget for this month."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(budgetRepositoryProvider)
        .clearForCategory(_month, categoryId);
  }

  Future<void> _addCategoryBudget(
    BuildContext context,
    WidgetRef ref,
    List<CategoryRow> budgetable,
  ) async {
    final chosen = await showGlassSheet<CategoryRow>(
      context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Pick a category'),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in budgetable)
                    ListTile(
                      leading: Text(
                        c.icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(c.name),
                      onTap: () => Navigator.of(context).pop(c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    final amount = await showAmountSheet(
      context,
      title: '${chosen.name} budget',
    );
    if (amount != null && amount.minor > 0) {
      await ref
          .read(budgetRepositoryProvider)
          .setForCategory(_month, chosen.id, amount);
    }
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.title,
    required this.spent,
    required this.budget,
    required this.onTap,
    this.onDelete,
    this.isIgnored,
    this.onToggleIgnored,
    this.suggestion,
    this.onApplySuggestion,
  });

  final String title;
  final Money spent;
  final Money? budget;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  /// Null = no ignore toggle shown (the overall-budget card). Non-null shows
  /// the "Ignore in totals" switch for a per-category card.
  final bool? isIgnored;
  final ValueChanged<bool>? onToggleIgnored;

  /// Null = no suggestion to show. Non-null shows a "Suggested ₹X" line that
  /// applies the amount immediately on tap, without opening the amount-entry
  /// sheet.
  final Money? suggestion;
  final VoidCallback? onApplySuggestion;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final has = budget != null && budget!.minor > 0;
    final rawRatio = has ? spent.ratioOf(budget!) : 0.0;
    final ratio = rawRatio.clamp(0.0, 1.0);
    final pct = (rawRatio * 100).round();

    // Usage state colour (FR-25 thresholds mirrored visually).
    final (barColor, statusText, statusColor) = !has
        ? (palette.textDim, 'Tap to set', palette.textDim)
        : pct >= 100
        ? (AppColors.red, 'Over budget', AppColors.red)
        : pct >= 80
        ? (AppColors.accent, 'Near limit', AppColors.accent)
        : (AppColors.primary, 'On track', palette.textDim);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  has
                      ? '${spent.format(locale: 'en_IN')} / ${budget!.format(locale: 'en_IN')}'
                      : 'No budget',
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: palette.textDim,
                    tooltip: 'Delete budget',
                  ),
              ],
            ),
            if (isIgnored != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ignore in totals',
                    style: TextStyle(fontSize: 11, color: palette.textDim),
                  ),
                  Switch(
                    value: isIgnored!,
                    activeTrackColor: AppColors.primary,
                    onChanged: onToggleIgnored,
                  ),
                ],
              ),
            ],
            if (!has && suggestion != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: onApplySuggestion,
                child: Text(
                  'Suggested ${suggestion!.format(locale: 'en_IN')} · tap to use',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: palette.line,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  has ? '$pct% used' : '—',
                  style: TextStyle(fontSize: 11, color: palette.textDim),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only summary of the sum of per-category budgets vs the overall
/// monthly budget. Shows a persistent (non-dismissible) warning line when
/// the total exceeds the overall budget — it's purely derived from live
/// data each rebuild, so it clears itself once the user fixes the numbers.
class _CategoryTotalCard extends StatelessWidget {
  const _CategoryTotalCard({required this.total, required this.overall});

  final Money total;
  final Money? overall;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final overrun = categoryBudgetOverrun(total, overall);

    if (overall == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Category budgets total',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  total.format(locale: 'en_IN'),
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Set overall budget to compare.',
              style: TextStyle(fontSize: 11, color: palette.textDim),
            ),
          ],
        ),
      );
    }

    final rawRatio = total.ratioOf(overall!);
    final ratio = rawRatio.clamp(0.0, 1.0);
    final pct = (rawRatio * 100).round();
    final barColor = overrun != null
        ? AppColors.red
        : pct >= 80
        ? AppColors.accent
        : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Category budgets total',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${total.format(locale: 'en_IN')} / ${overall!.format(locale: 'en_IN')}',
                style: TextStyle(fontSize: 12, color: palette.textDim),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: palette.line,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          if (overrun != null) ...[
            const SizedBox(height: 8),
            Text(
              'Exceeds monthly budget by ${overrun.format(locale: 'en_IN')}. '
              'Increase monthly budget or reduce category budgets.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddBudgetButton extends StatelessWidget {
  const _AddBudgetButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final label = enabled
        ? 'Set budget for a category'
        : 'All categories have budgets';
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.line),
          ),
          alignment: Alignment.center,
          child: Text(
            enabled
                ? '+ Set budget for a category'
                : 'All categories have budgets',
            style: TextStyle(
              color: enabled ? AppColors.primary : palette.textDim,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// One not-yet-budgeted category's suggested next-month amount — tapping
/// applies it immediately via [onApply]; the category then re-renders as a
/// normal `_BudgetCard` (still editable) on the next build, since it now has
/// a budget row.
class _SuggestedCategoryRow extends StatelessWidget {
  const _SuggestedCategoryRow({
    required this.category,
    required this.recommendation,
    required this.onApply,
  });

  final CategoryRow category;
  final BudgetRecommendation recommendation;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onApply,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${category.icon} ${category.name}',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              recommendation.monthsUsed < 6
                  ? 'Suggested ${recommendation.amount.format(locale: 'en_IN')} (${recommendation.monthsUsed}mo)'
                  : 'Suggested ${recommendation.amount.format(locale: 'en_IN')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

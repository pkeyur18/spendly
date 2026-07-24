import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/async_state_views.dart';
import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';
import '../home/dashboard_providers.dart';
import '../reports/report_providers.dart';
import 'budget_repository.dart';

/// Budget Setup (FR-23,24) — prototype phone 6. Overall + per-category budgets,
/// scoped per month with prev/next navigation and a manual carry-forward
/// action; each card shows a read-only usage bar (spent / budget) coloured by
/// state.
class BudgetSetupScreen extends ConsumerStatefulWidget {
  const BudgetSetupScreen({super.key});

  @override
  ConsumerState<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends ConsumerState<BudgetSetupScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _stepMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final monthKey = monthKeyFor(_month);
    final overallAsync = ref.watch(overallBudgetForMonthProvider(monthKey));
    final activeAsync = ref.watch(activeCategoriesProvider);

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
      final perCategory = ref.watch(perCategoryBudgetsForMonthProvider(monthKey));
      final catsById = ref.watch(categoriesByIdProvider);
      final report = ref.watch(reportProvider(monthBounds(_month))).value;
      final spentByCat = {
        for (final (cat, money, _) in report?.breakdown ?? const <CategorySlice>[])
          cat.id: money,
      };
      final monthTotal = report?.total ?? Money.zero;

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
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: OutlinedButton(
                onPressed: () => _carryForward(context, ref),
                child: Text(
                  'Carry forward from ${DateFormat('MMMM').format(DateTime(_month.year, _month.month - 1, 1))}',
                ),
              ),
            ),
          _BudgetCard(
            title: 'Overall monthly budget',
            spent: monthTotal,
            budget: overall,
            onTap: () => _editOverall(context, ref, overall),
          ),
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
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
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

  Future<void> _carryForward(BuildContext context, WidgetRef ref) async {
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
    if (amount == null) return;
    final repo = ref.read(budgetRepositoryProvider);
    // Zero clears the budget (FR-24 — a way to remove it).
    amount.minor > 0
        ? await repo.setForCategory(_month, categoryId, amount)
        : await repo.clearForCategory(_month, categoryId);
  }

  Future<void> _addCategoryBudget(
    BuildContext context,
    WidgetRef ref,
    List<CategoryRow> budgetable,
  ) async {
    final chosen = await showModalBottomSheet<CategoryRow>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Pick a category'),
            ),
            for (final c in budgetable)
              ListTile(
                leading: Text(c.icon, style: const TextStyle(fontSize: 20)),
                title: Text(c.name),
                onTap: () => Navigator.of(context).pop(c),
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
  });

  final String title;
  final Money spent;
  final Money? budget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final has = budget != null && budget!.minor > 0;
    final ratio = has ? spent.ratioOf(budget!).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100).round();

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

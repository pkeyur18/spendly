import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../budgets/budget_pace.dart';
import '../budgets/budget_repository.dart';
import '../dev/debug_data_screen.dart';
import '../budgets/budget_setup_screen.dart';
import '../expenses/all_transactions_screen.dart';
import '../expenses/expense_repository.dart';
import '../expenses/widgets/expense_tile.dart';
import '../profile/profile_provider.dart';
import 'dashboard_providers.dart';
import 'widgets/spend_donut.dart';
import 'widgets/trend_bars.dart';

/// Home dashboard (FR-12–16) — prototype phone 1.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final recent = ref.watch(recentExpensesProvider);
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              child: const FittedBox(
                child: Text(
                  '₹',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('Spendly'),
          ],
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Debug data',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebugDataScreen()),
              ),
              icon: const Icon(Icons.bug_report_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _greeting(context, palette, profile?.name ?? ''),
          const _HeroCard(),
          const SectionTitle('Where it went'),
          const SpendDonut(),
          const SectionTitle('Last 6 months'),
          const TrendBars(),
          SectionTitle(
            'Recent',
            actionLabel: 'View all',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AllTransactionsScreen(
                  initialRange: dayBounds(DateTime.now()),
                  title: 'Today',
                ),
              ),
            ),
          ),
          if (recent.isEmpty)
            _emptyRecent(palette)
          else
            for (final (expense, category) in recent)
              ExpenseTile(expense: expense, category: category),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _greeting(BuildContext context, AppPalette palette, String name) {
    final now = DateTime.now();
    final part = now.hour < 12
        ? 'morning'
        : now.hour < 17
        ? 'afternoon'
        : 'evening';
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    final baseStyle = Theme.of(context).textTheme.headlineMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xl,
      ),
      child: firstName.isEmpty
          ? Text('Good $part', style: baseStyle)
          : Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  TextSpan(text: 'Good $part, '),
                  TextSpan(
                    text: firstName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _emptyRecent(AppPalette palette) {
    return AppCard(
      child: Text(
        'No expenses yet — tap + to log one.',
        style: TextStyle(color: palette.textDim, fontSize: 13),
      ),
    );
  }
}

/// Hero gradient card: month total + budget bar (FR-12, FR-16).
class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(monthTotalProvider);
    final budget = effectiveOverallBudget(
      ref.watch(overallBudgetProvider).value,
      ref.watch(perCategoryBudgetsProvider),
      ignoredCategoryIds(ref.watch(categoriesByIdProvider)),
    );

    final hasBudget = budget != null && budget.minor > 0;
    final rawRatio = hasBudget ? total.ratioOf(budget) : 0.0;
    final ratio = rawRatio.clamp(0.0, 1.0);
    final barColor = ratio >= 1.0
        ? AppColors.red
        : ratio >= 0.8
        ? AppColors.accent
        : Colors.white;
    final left = hasBudget
        ? Money.fromMinor((budget.minor - total.minor).clamp(0, budget.minor))
        : null;
    final pace = budgetPace(spent: total, budget: budget, now: DateTime.now());

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Spent this month',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              IconButton(
                tooltip: 'Set budget',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BudgetSetupScreen()),
                ),
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            total.format(locale: 'en_IN'),
            style: const TextStyle(
              fontFamily: 'Sora',
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          if (hasBudget) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(rawRatio * 100).round()}% of ${budget.format(locale: 'en_IN')} budget',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  '${left!.format(locale: 'en_IN')} left',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            if (pace != null) ...[
              const SizedBox(height: 10),
              _PaceLine(pace: pace),
            ],
          ] else
            const Text(
              'No monthly budget set',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// The one line on the hero that turns "61% of budget" into something the user
/// can act on today. Status is carried by the words and the icon, never by
/// colour alone.
class _PaceLine extends StatelessWidget {
  const _PaceLine({required this.pace});

  final BudgetPace pace;

  @override
  Widget build(BuildContext context) {
    final days = pace.daysLeft == 1 ? '1 day' : '${pace.daysLeft} days';
    final perDay = pace.perDayLeft.format(locale: 'en_IN');

    final (icon, label) = switch (pace.status) {
      PaceStatus.onTrack => (
        Icons.trending_flat_rounded,
        'On track · $perDay/day for $days',
      ),
      PaceStatus.overPace => (
        Icons.trending_up_rounded,
        'Over pace · $perDay/day for $days',
      ),
      PaceStatus.overBudget => (
        Icons.warning_amber_rounded,
        'Over budget by ${pace.overspend.format(locale: 'en_IN')}',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.icon),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

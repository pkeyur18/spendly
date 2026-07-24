import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../budgets/budget_repository.dart';
import '../categories/category_manager_screen.dart';
import '../dev/debug_data_screen.dart';
import '../expenses/expense_repository.dart';
import '../expenses/quick_add_screen.dart';
import '../profile/avatar.dart';
import '../profile/profile_provider.dart';
import '../profile/profile_screen.dart';
import '../reports/monthly_report_screen.dart';
import '../settings/theme_mode_provider.dart';
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
          IconButton(
            tooltip: 'Theme',
            onPressed: () => _cycleTheme(ref),
            icon: const Icon(Icons.brightness_6_outlined),
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
          const SectionTitle('Recent'),
          if (recent.isEmpty)
            _emptyRecent(palette)
          else
            for (final (expense, category) in recent)
              _TransactionTile(expense: expense, category: category),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(19),
        ),
        child: FloatingActionButton(
          onPressed: () => _openQuickAdd(context),
          tooltip: 'Add expense',
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      bottomNavigationBar: _BottomNav(palette: palette, profile: profile),
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
    final greeting = firstName.isEmpty
        ? 'Good $part'
        : 'Good $part, $firstName';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xl,
      ),
      child: Text(greeting, style: Theme.of(context).textTheme.headlineMedium),
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

  void _cycleTheme(WidgetRef ref) {
    final current = ref.read(themeModeProvider).value ?? ThemeMode.system;
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(current) + 1) % order.length];
    ref.read(themeModeProvider.notifier).setMode(next);
  }

  void _openQuickAdd(BuildContext context, {ExpenseRow? editing}) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => QuickAddScreen(editing: editing)));
  }
}

/// Hero gradient card: month total + budget bar (FR-12, FR-16).
class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(monthTotalProvider);
    final budget = ref.watch(overallBudgetProvider).value;

    final hasBudget = budget != null && budget.minor > 0;
    final ratio = hasBudget ? total.ratioOf(budget).clamp(0.0, 1.0) : 0.0;
    final left = hasBudget
        ? Money.fromMinor((budget.minor - total.minor).clamp(0, budget.minor))
        : null;

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
          const Text(
            'Spent this month',
            style: TextStyle(color: Colors.white70, fontSize: 13),
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
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(ratio * 100).round()}% of ${budget.format(locale: 'en_IN')} budget',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  '${left!.format(locale: 'en_IN')} left',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ] else
            const Text(
              'Set a monthly budget in Categories → Budgets',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.expense, required this.category});

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
                      _relativeTime(expense.date),
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

  String _relativeTime(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final time = DateFormat.jm().format(d);
    if (diff == 0) return 'Today · $time';
    if (diff == 1) return 'Yesterday · $time';
    return DateFormat.MMMd().format(d);
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.palette, required this.profile});

  final AppPalette palette;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    void soon(String label) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label — coming soon')));

    Widget item(
      IconData icon,
      String label, {
      bool active = false,
      VoidCallback? onTap,
      Widget? leading,
    }) {
      return IconButton(
        onPressed: onTap ?? () => soon(label),
        tooltip: label,
        icon:
            leading ??
            Icon(icon, color: active ? AppColors.primary : palette.textDim),
      );
    }

    return BottomAppBar(
      color: palette.card,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          item(Icons.home_rounded, 'Home', active: true, onTap: () {}),
          item(
            Icons.bar_chart_rounded,
            'Reports',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MonthlyReportScreen(month: DateTime.now()),
                ),
              );
            },
          ),
          const SizedBox(width: 40),
          item(
            Icons.sell_rounded,
            'Categories',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CategoryManagerScreen(),
                ),
              );
            },
          ),
          item(
            Icons.account_circle_rounded,
            'Profile',
            leading: ProfileAvatar(
              name: profile?.name ?? '',
              photoPath: profile?.photoPath,
              avatarColorIndex: profile?.avatarColorIndex,
              size: 26,
              fontSize: 11,
            ),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
        ],
      ),
    );
  }
}

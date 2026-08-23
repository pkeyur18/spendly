import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart' show monthKeyFor;
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../accounts/account_repository.dart';
import '../budgets/budget_repository.dart';
import '../expenses/all_transactions_screen.dart';
import '../expenses/expense_repository.dart';
import '../expenses/receipt_repository.dart';
import '../home/dashboard_providers.dart';
import '../home/widgets/spend_donut.dart';
import '../profile/profile_provider.dart';
import '../tags/tag_report_screen.dart';
import '../tags/tag_repository.dart';
import 'custom_report_screen.dart';
import 'report_providers.dart';
import 'report_widgets.dart';

/// Monthly report (FR-17, FR-20) — prototype phone 3. Auto-notified at month
/// end; also reachable from the Reports tab (defaults to the current month).
class MonthlyReportScreen extends ConsumerWidget {
  const MonthlyReportScreen({super.key, required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (start, end) = monthBounds(month);
    final title = '${DateFormat('MMMM').format(month)} Report';
    final async = ref.watch(reportProvider((start, end)));
    final byId = ref.watch(categoriesByIdProvider);
    final tagById = ref.watch(tagsByIdProvider);
    final accountById = ref.watch(accountsByIdProvider);
    final withReceipt = ref.watch(expenseIdsWithReceiptProvider).value ?? const {};
    final overall = effectiveOverallBudget(
      ref.watch(overallBudgetForMonthProvider(monthKeyFor(month))).value,
      ref.watch(perCategoryBudgetsForMonthProvider(monthKeyFor(month))),
      ignoredCategoryIds(byId),
    );
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Trips',
            icon: const Icon(Icons.card_travel_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TagReportScreen())),
          ),
          IconButton(
            tooltip: 'Custom range',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomReportScreen()),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load this report.',
          onRetry: () => ref.invalidate(reportProvider((start, end))),
        ),
        data: (data) {
          if (data.txnCount == 0) {
            return const EmptyView(
              icon: Icons.receipt_long_outlined,
              message: 'No transactions this month yet.',
            );
          }
          final budgetUsed = (overall == null || overall.minor <= 0)
              ? '—'
              : '${(data.total.ratioOf(overall) * 100).round()}%';
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ReportHero(label: 'Total spent', data: data),
              const SizedBox(height: AppSpacing.lg),
              StatGrid(
                stats: [
                  ('Daily average', data.dailyAverage.format(locale: 'en_IN')),
                  ('Transactions', '${data.txnCount}'),
                  ('Top category', data.topCategory?.$1.name ?? '—'),
                  ('Budget used', budgetUsed),
                ],
              ),
              const SectionTitle('By category'),
              DonutChart(slices: data.breakdown, total: data.total),
              const SectionTitle('Top 5 expenses'),
              TopExpensesCard(data: data, byId: byId),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AllTransactionsScreen(
                      initialRange: (start, end),
                      title: title,
                      showRangeSwitcher: true,
                    ),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('View all transactions'),
              ),
              const SizedBox(height: AppSpacing.xxl),
              ExportRow(
                data: data,
                byId: byId,
                title: title,
                profile: profile,
                tagById: tagById,
                accountById: accountById,
                expenseIdsWithReceipt: withReceipt,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

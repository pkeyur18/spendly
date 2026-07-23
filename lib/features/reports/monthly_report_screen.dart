import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../budgets/budget_repository.dart';
import '../expenses/expense_repository.dart';
import '../home/dashboard_providers.dart';
import '../home/widgets/spend_donut.dart';
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
    final overall = ref.watch(overallBudgetProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Custom range',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomReportScreen())),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load report:\n$e')),
        data: (data) {
          final budgetUsed = (overall == null || overall.minor <= 0)
              ? '—'
              : '${(data.total.ratioOf(overall) * 100).round()}%';
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ReportHero(label: 'Total spent', data: data),
              const SizedBox(height: AppSpacing.lg),
              StatGrid(stats: [
                ('Daily average', data.dailyAverage.format(locale: 'en_IN')),
                ('Transactions', '${data.txnCount}'),
                ('Top category', data.topCategory?.$1.name ?? '—'),
                ('Budget used', budgetUsed),
              ]),
              const SectionTitle('By category'),
              DonutChart(slices: data.breakdown, total: data.total),
              const SectionTitle('Top 5 expenses'),
              TopExpensesCard(data: data, byId: byId),
              const SizedBox(height: AppSpacing.xxl),
              ExportRow(data: data, byId: byId, title: title),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

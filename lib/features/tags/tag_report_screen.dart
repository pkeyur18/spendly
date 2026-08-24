import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/fx.dart';
import '../../core/money/fx_rate_service.dart' show homeCurrencyCode;
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../accounts/account_repository.dart';
import '../expenses/all_transactions_screen.dart' show groupExpensesByDay;
import '../expenses/expense_repository.dart';
import '../expenses/receipt_repository.dart';
import '../expenses/widgets/expense_tile.dart';
import '../home/dashboard_providers.dart';
import '../home/widgets/spend_donut.dart';
import '../home/widgets/trend_bars.dart';
import '../profile/profile_provider.dart';
import '../reports/report_model.dart';
import '../reports/report_providers.dart';
import '../reports/report_widgets.dart';
import 'tag_manager_screen.dart';
import 'tag_repository.dart';

/// Trips report (vacation/trip expense tracking): lists every active trip
/// with its lifetime total + expense count, and drills into a per-trip
/// report reusing the same [ReportHero]/[DonutChart]/export widgets as the
/// date-range reports. Trip totals are purely additive — they don't change
/// any category, budget, or date-range total.
class TagReportScreen extends ConsumerWidget {
  const TagReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(activeTagsProvider);
    final totalsAsync = ref.watch(tagTotalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            tooltip: 'Manage trips',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TagManagerScreen())),
          ),
        ],
      ),
      body: tagsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load trips.",
          onRetry: () => ref.invalidate(activeTagsProvider),
        ),
        data: (tags) {
          if (tags.isEmpty) {
            return const EmptyView(
              icon: Icons.card_travel_outlined,
              message: 'No trips yet — tap the edit icon above to add one.',
            );
          }
          final totals = totalsAsync.value ?? const <int, Money>{};
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              for (final tag in tags)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TagRow(tag: tag, total: totals[tag.id] ?? Money.zero),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TagRow extends ConsumerWidget {
  const _TagRow({required this.tag, required this.total});

  final TagRow tag;
  final Money total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final color = Color(tag.colorValue);
    final count = ref.watch(tagExpenseCountProvider(tag.id)).value ?? 0;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TagDetailScreen(tag: tag))),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.card_travel_outlined, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  count == 1 ? '1 expense' : '$count expenses',
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
              ],
            ),
          ),
          Text(
            total.format(locale: 'en_IN'),
            style: const TextStyle(fontFamily: 'Sora', fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// One trip's report — same layout as [CustomReportScreen] (hero, trend,
/// category breakdown, transactions, export), scoped to this tag's expenses
/// instead of a date range.
class TagDetailScreen extends ConsumerWidget {
  const TagDetailScreen({super.key, required this.tag});

  final TagRow tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tagReportProvider(tag.id));
    final byId = ref.watch(categoriesByIdProvider);
    final accountById = ref.watch(accountsByIdProvider);
    final withReceipt = ref.watch(expenseIdsWithReceiptProvider).value ?? const {};
    final profile = ref.watch(profileProvider).value;
    final df = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(title: Text(tag.name)),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load this trip.",
          onRetry: () => ref.invalidate(tagReportProvider(tag.id)),
        ),
        data: (data) => data.txnCount == 0
            ? const EmptyView(
                icon: Icons.receipt_long_outlined,
                message: 'No expenses tagged to this trip yet.',
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  ReportHero(label: tag.name, data: data),
                  if (tag.isTravel) _TravelSummary(tag: tag, data: data),
                  const SectionTitle('Spending trend'),
                  TrendBarsView(bars: data.weekly),
                  const SectionTitle('By category'),
                  DonutChart(slices: data.breakdown, total: data.total),
                  const SectionTitle('Transactions'),
                  for (final entry in groupExpensesByDay(
                    data.expenses,
                  ).entries) ...[
                    DayGroupHeader(
                      entry.key,
                      total: entry.value.fold(
                        Money.zero,
                        (sum, e) => sum + e.amount,
                      ),
                    ),
                    for (final e in entry.value)
                      ExpenseTile(expense: e, category: byId[e.categoryId]),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  ExportRow(
                    data: data,
                    byId: byId,
                    title:
                        '${tag.name} (${df.format(data.start)} - '
                        '${df.format(data.end.subtract(const Duration(days: 1)))})',
                    profile: profile,
                    // No tagById: every row here already belongs to this one
                    // trip, so a per-row Trip column would just repeat the
                    // same name on every line rather than add information.
                    accountById: accountById,
                    expenseIdsWithReceipt: withReceipt,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
      ),
    );
  }
}

/// Foreign-currency summary for a trip abroad: what was actually spent in the
/// local currency, and the rate that produced the home-currency total above.
///
/// Both figures are derived from the expenses already loaded for the report —
/// no extra query, and nothing here is stored. The average rate is
/// `sum(home) / sum(foreign)`, so a rate edited mid-trip shows up honestly as
/// a blend of everything actually used rather than whatever the tag happens
/// to hold right now.
class _TravelSummary extends StatelessWidget {
  const _TravelSummary({required this.tag, required this.data});

  final TagRow tag;
  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    var fxMinor = 0;
    var homeMinor = 0;
    // ponytail: sums the raw expense list, so a travel expense in a
    // budget-ignored category counts here but not in the hero total above.
    // Tagging rent to a holiday isn't a real case; filter by
    // ignoredCategoryIds if it ever becomes one.
    for (final e in data.expenses) {
      if (e.fxCurrency != tag.fxCurrency || e.fxAmountMinor == null) continue;
      fxMinor += e.fxAmountMinor!;
      homeMinor += e.amountMinor;
    }
    if (fxMinor == 0) return const SizedBox.shrink();

    final avg = averageRateMicros(homeMinor, fxMinor);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        child: Column(
          children: [
            Text(
              'Spent abroad',
              style: TextStyle(fontSize: 12, color: palette.textDim),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              Money.fromMinor(fxMinor).formatAs(tag.fxCurrency!),
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            if (avg != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'avg 1 ${tag.fxCurrency} = ${rateToString(avg)} '
                '$homeCurrencyCode',
                style: TextStyle(fontSize: 11.5, color: palette.textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

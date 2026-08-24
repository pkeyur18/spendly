import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../accounts/account_repository.dart';
import '../expenses/all_transactions_screen.dart' show groupExpensesByDay;
import '../expenses/receipt_repository.dart';
import '../expenses/widgets/expense_tile.dart';
import '../home/dashboard_providers.dart';
import '../home/widgets/spend_donut.dart';
import '../home/widgets/trend_bars.dart';
import '../ledger/cashflow_math.dart';
import '../ledger/ledger_repository.dart';
import '../profile/profile_provider.dart';
import '../tags/tag_repository.dart';
import 'report_providers.dart';
import 'report_widgets.dart';

/// Custom-range report (FR-19) — prototype phone 4. Quick chips + native
/// date-range picker; recomputes via [reportProvider] on range change.
class CustomReportScreen extends ConsumerStatefulWidget {
  const CustomReportScreen({super.key});

  @override
  ConsumerState<CustomReportScreen> createState() => _CustomReportScreenState();
}

class _CustomReportScreenState extends ConsumerState<CustomReportScreen> {
  static const _chips = ['Last 7 days', 'Last 30 days', 'This year', 'Custom'];
  int _selected = 1; // Last 30 days
  late DateRange _range = _presetRange(1);

  /// Half-open [start, end) for a preset chip, anchored to today.
  DateRange _presetRange(int chip) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1)); // include today
    switch (chip) {
      case 0:
        return (today.subtract(const Duration(days: 6)), end);
      case 2:
        return (DateTime(now.year, 1, 1), end);
      case 1:
      default:
        return (today.subtract(const Duration(days: 29)), end);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: _range.$1,
        end: _range.$2.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final end = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1)); // half-open, inclusive of picked end
    setState(() {
      _selected = 3;
      _range = (start, end);
    });
  }

  void _selectChip(int i) {
    if (i == 3) {
      _pickCustom();
      return;
    }
    setState(() {
      _selected = i;
      _range = _presetRange(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final df = DateFormat('MMM d, yyyy');
    final async = ref.watch(reportProvider(_range));
    final byId = ref.watch(categoriesByIdProvider);
    final tagById = ref.watch(tagsByIdProvider);
    final accountById = ref.watch(accountsByIdProvider);
    final withReceipt = ref.watch(expenseIdsWithReceiptProvider).value ?? const {};
    final profile = ref.watch(profileProvider).value;
    final incomeTotal =
        ref.watch(incomeTotalByRangeProvider(_range)).value ?? Money.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Custom report')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SectionTitle('Quick ranges'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < _chips.length; i++)
                ChoiceChip(
                  label: Text(_chips[i]),
                  selected: _selected == i,
                  onSelected: (_) => _selectChip(i),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _selected == i ? Colors.white : palette.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: palette.card,
                  shape: StadiumBorder(side: BorderSide(color: palette.line)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _RangeBox(label: 'From', value: df.format(_range.$1)),
              const SizedBox(width: AppSpacing.md),
              _RangeBox(
                label: 'To',
                value: df.format(_range.$2.subtract(const Duration(days: 1))),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: LoadingView(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(40),
              child: ErrorView(
                message: 'Could not load this report.',
                onRetry: () => ref.invalidate(reportProvider(_range)),
              ),
            ),
            data: (data) => data.txnCount == 0
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: EmptyView(
                      icon: Icons.receipt_long_outlined,
                      message: 'No transactions in this range.',
                    ),
                  )
                : Column(
                    children: [
                      ReportHero(label: 'Total in range', data: data),
                      // Only shown once income has actually been logged for
                      // this range — see the same gate on the monthly report.
                      if (incomeTotal.minor > 0) ...[
                        const SizedBox(height: AppSpacing.lg),
                        StatGrid(
                          stats: [
                            ('Income', incomeTotal.format(locale: 'en_IN')),
                            (
                              'Savings rate',
                              '${computeCashflow(income: incomeTotal, expense: data.total).savingsRatePercent}%',
                            ),
                          ],
                        ),
                      ],
                      const SectionTitle('Spending trend'),
                      TrendBarsView(bars: data.weekly),
                      const SectionTitle('By category'),
                      DonutChart(slices: data.breakdown, total: data.total),
                      const SectionTitle('Transactions'),
                      for (final entry
                          in groupExpensesByDay(data.expenses).entries) ...[
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
                            'Report ${DateFormat('MMM d').format(_range.$1)} to ${DateFormat('MMM d').format(_range.$2.subtract(const Duration(days: 1)))}',
                        profile: profile,
                        tagById: tagById,
                        accountById: accountById,
                        expenseIdsWithReceipt: withReceipt,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RangeBox extends StatelessWidget {
  const _RangeBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Expanded(
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
            Text(label, style: TextStyle(fontSize: 11, color: palette.textDim)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

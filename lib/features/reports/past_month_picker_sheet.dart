import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass.dart';
import '../expenses/expense_repository.dart';
import '../home/dashboard_providers.dart' show sumMoney;

/// One row in the past-month picker: a calendar month plus its already-
/// bucketed totals, so the sheet can preview spend before the user commits
/// to opening the full report.
class MonthSummary {
  MonthSummary(this.month, this.total, this.count);
  final DateTime month;
  final Money total;
  final int count;
}

/// Expenses for the 12 calendar months before the current one (current month
/// excluded — it already has its own export path from the Reports tab).
final _pastTwelveMonthsExpensesProvider = StreamProvider<List<ExpenseRow>>((
  ref,
) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 12, 1);
  final end = DateTime(now.year, now.month, 1);
  return ref.watch(expenseRepositoryProvider).watchInRange(start, end);
});

/// Buckets [expenses] into the 12 months before [now], most recent first.
List<MonthSummary> bucketPastMonths(
  List<ExpenseRow> expenses,
  DateTime now,
) {
  return [
    for (var i = 1; i <= 12; i++)
      () {
        final m = DateTime(now.year, now.month - i, 1);
        final inMonth = expenses
            .where((e) => e.date.year == m.year && e.date.month == m.month)
            .toList();
        return MonthSummary(m, sumMoney(inMonth), inMonth.length);
      }(),
  ];
}

/// Sheet for picking one of the last 12 months to export. Returns the picked
/// month's first-of-month [DateTime], or null if dismissed.
Future<DateTime?> showPastMonthPickerSheet(BuildContext context) {
  return showGlassSheet<DateTime>(
    context,
    builder: (_) => const _PastMonthPickerSheet(),
  );
}

class _PastMonthPickerSheet extends ConsumerWidget {
  const _PastMonthPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final async = ref.watch(_pastTwelveMonthsExpensesProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Export a past month',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    "Couldn't load past months.",
                    style: TextStyle(color: palette.textDim),
                  ),
                ),
                data: (expenses) {
                  final months = bucketPastMonths(expenses, DateTime.now());
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: months.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: palette.line),
                    itemBuilder: (context, i) {
                      final m = months[i];
                      return ListTile(
                        title: Text(DateFormat('MMMM yyyy').format(m.month)),
                        subtitle: Text(
                          m.count == 0
                              ? 'No transactions'
                              : '${m.count} transaction${m.count == 1 ? '' : 's'}',
                          style: TextStyle(color: palette.textDim),
                        ),
                        trailing: Text(
                          m.total.format(locale: 'en_IN'),
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () =>
                            Navigator.of(context).pop<DateTime>(m.month),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

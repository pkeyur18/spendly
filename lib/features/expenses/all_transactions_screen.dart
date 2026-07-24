import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_state_views.dart';
import '../home/dashboard_providers.dart';
import 'expense_repository.dart';
import 'widgets/expense_tile.dart';

/// Groups a newest-first expense list into calendar-day buckets, preserving
/// order (most recent day first, newest-within-day first).
Map<DateTime, List<ExpenseRow>> groupExpensesByDay(List<ExpenseRow> expenses) {
  final groups = <DateTime, List<ExpenseRow>>{};
  for (final e in expenses) {
    final day = DateTime(e.date.year, e.date.month, e.date.day);
    groups.putIfAbsent(day, () => []).add(e);
  }
  return groups;
}

bool _isCalendarMonth((DateTime, DateTime) range) {
  final bounds = monthBounds(range.$1);
  return bounds.$1 == range.$1 && bounds.$2 == range.$2;
}

/// Full transaction list for a date range, grouped by day. Opened either
/// locked to today (from Home, no switcher) or with a month/custom-range
/// switcher (from the report screen).
class AllTransactionsScreen extends ConsumerStatefulWidget {
  const AllTransactionsScreen({
    super.key,
    required this.initialRange,
    required this.title,
    this.showRangeSwitcher = false,
  });

  final (DateTime, DateTime) initialRange;
  final String title;
  final bool showRangeSwitcher;

  @override
  ConsumerState<AllTransactionsScreen> createState() =>
      _AllTransactionsScreenState();
}

/// Page size for the transactions list — how many rows load up front and how
/// many each scroll-to-bottom adds. Keeps memory/build bounded on huge ranges.
const _pageSize = 100;

class _AllTransactionsScreenState extends ConsumerState<AllTransactionsScreen> {
  late (DateTime, DateTime) _range = widget.initialRange;
  int _limit = _pageSize;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Grow the limit when the user nears the bottom and the current page is full
  /// (a short page means the range is exhausted — nothing more to load).
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 400) return;
    final loaded = ref
        .read(expensesInRangeProvider((_range.$1, _range.$2, _limit)))
        .asData
        ?.value
        .length;
    if (loaded != null && loaded >= _limit) {
      setState(() => _limit += _pageSize);
    }
  }

  void _stepMonth(int delta) {
    final anchor = DateTime(_range.$1.year, _range.$1.month + delta, 1);
    setState(() {
      _range = monthBounds(anchor);
      _limit = _pageSize;
    });
  }

  Future<void> _pickCustomRange() async {
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
    final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final end = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1));
    setState(() {
      _range = (start, end);
      _limit = _pageSize;
    });
  }

  String get _title {
    if (!widget.showRangeSwitcher) return widget.title;
    if (_isCalendarMonth(_range)) {
      return DateFormat('MMMM yyyy').format(_range.$1);
    }
    final df = DateFormat('MMM d');
    return '${df.format(_range.$1)} – ${df.format(_range.$2.subtract(const Duration(days: 1)))}';
  }

  @override
  Widget build(BuildContext context) {
    final key = (_range.$1, _range.$2, _limit);
    final async = ref.watch(expensesInRangeProvider(key));
    final byId = ref.watch(categoriesByIdProvider);
    final monthMode = widget.showRangeSwitcher && _isCalendarMonth(_range);
    final now = DateTime.now();
    final atCurrentMonth =
        monthMode &&
        _range.$1.year == now.year &&
        _range.$1.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (monthMode) ...[
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _stepMonth(-1),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: atCurrentMonth ? null : () => _stepMonth(1),
            ),
          ],
          if (widget.showRangeSwitcher)
            IconButton(
              tooltip: 'Custom range',
              icon: const Icon(Icons.tune_rounded),
              onPressed: _pickCustomRange,
            ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load transactions.',
          onRetry: () => ref.invalidate(expensesInRangeProvider(key)),
        ),
        data: (expenses) {
          if (expenses.isEmpty) {
            return const EmptyView(
              icon: Icons.receipt_long_outlined,
              message: 'No transactions in this range.',
            );
          }
          // Flatten day-groups into a single list (DateTime = header,
          // ExpenseRow = tile) so ListView.builder can lazily build only the
          // visible rows instead of every tile up front.
          final items = <Object>[];
          for (final entry in groupExpensesByDay(expenses).entries) {
            items.add(entry.key);
            items.addAll(entry.value);
          }
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is DateTime) return DayGroupHeader(item);
              final e = item as ExpenseRow;
              return ExpenseTile(expense: e, category: byId[e.categoryId]);
            },
          );
        },
      ),
    );
  }
}

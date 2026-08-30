import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/repeat_picker.dart';
import '../accounts/account_picker_sheet.dart';
import '../accounts/account_repository.dart';
import '../expenses/expense_repository.dart' show monthBounds;
import '../expenses/recurring_schedule.dart';
import '../expenses/widgets/expense_tile.dart' show relativeDayLabel;
import 'ledger_repository.dart';

/// Groups [entries] by calendar month (1-12), preserving each group's
/// existing relative order. Generic and DB-agnostic so it's unit-testable
/// without a Drift row — used by [_YearGroupedList] to split the "Year"
/// toggle's flat list into per-month sections without touching how the
/// data is fetched.
Map<int, List<T>> groupByMonth<T>(
  Iterable<T> entries,
  DateTime Function(T) dateOf,
) {
  final grouped = <int, List<T>>{};
  for (final e in entries) {
    grouped.putIfAbsent(dateOf(e).month, () => []).add(e);
  }
  return grouped;
}

/// Income (schema v15) — this month's entries by default, with a toggle to
/// the full current year grouped by month (2026-08-24 redesign). Reached
/// from Profile, same shape as Accounts/Recurring.
///
/// The month/year split is a pure UI-layer transform over the same
/// all-time stream [allIncomeProvider] already fetches — no new query.
/// `_fullYear` is view-only state, same pattern as
/// `AccountDetailScreen`'s own month/year toggle.
class IncomeScreen extends ConsumerStatefulWidget {
  const IncomeScreen({super.key});

  @override
  ConsumerState<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends ConsumerState<IncomeScreen> {
  bool _fullYear = false;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final async = ref.watch(allIncomeProvider);
    final (start, end) = monthBounds(DateTime.now());
    final monthTotal = ref.watch(incomeTotalByRangeProvider((start, end)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Income'),
        actions: [
          IconButton(
            tooltip: 'Add income',
            onPressed: () => showIncomeEditSheet(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load income.",
          onRetry: () => ref.invalidate(allIncomeProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyView(
              icon: Icons.savings_outlined,
              message: 'No income logged yet. Tap + to add your first entry.',
            );
          }
          final now = DateTime.now();
          final yearEntries = entries
              .where((e) => e.date.year == now.year)
              .toList();
          final monthEntries = yearEntries
              .where((e) => e.date.month == now.month)
              .toList();
          final yearTotal = yearEntries.fold(
            Money.zero,
            (acc, e) => acc + e.amount,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fullYear ? 'This year' : 'This month',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textDim,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (_fullYear
                                    ? yearTotal
                                    : (monthTotal.value ?? Money.zero))
                                .format(locale: 'en_IN'),
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Month'),
                          selected: !_fullYear,
                          onSelected: (_) => setState(() => _fullYear = false),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          label: const Text('Year'),
                          selected: _fullYear,
                          onSelected: (_) => setState(() => _fullYear = true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _fullYear
                    ? _YearGroupedList(entries: yearEntries, year: now.year)
                    : _MonthList(entries: monthEntries),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Current-month flat list — the default view.
class _MonthList extends StatelessWidget {
  const _MonthList({required this.entries});
  final List<LedgerEntryRow> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyView(
        icon: Icons.savings_outlined,
        message: 'No income logged this month yet.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _IncomeTile(entry: entries[i]),
    );
  }
}

/// Full current-year list, grouped by month (most recent month first) — the
/// "Year" toggle state. [entries] is already filtered to [year] by the
/// caller; grouping and sorting is the only work done here, over data
/// already fetched by [allIncomeProvider].
class _YearGroupedList extends StatelessWidget {
  const _YearGroupedList({required this.entries, required this.year});
  final List<LedgerEntryRow> entries;
  final int year;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyView(
        icon: Icons.savings_outlined,
        message: 'No income logged this year yet.',
      );
    }
    final grouped = groupByMonth(entries, (e) => e.date);
    final monthsDesc = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        for (final month in monthsDesc) ...[
          SectionTitle(DateFormat('MMMM').format(DateTime(year, month))),
          for (final e in grouped[month]!) _IncomeTile(entry: e),
        ],
      ],
    );
  }
}

class _IncomeTile extends ConsumerWidget {
  const _IncomeTile({required this.entry});
  final LedgerEntryRow entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final accountById = ref.watch(accountsByIdProvider);
    final account = entry.accountId == null
        ? null
        : accountById[entry.accountId];
    final title = entry.sourceLabel?.isNotEmpty == true
        ? entry.sourceLabel!
        : 'Income';
    final subtitle = account == null
        ? relativeDayLabel(entry.date)
        : '${relativeDayLabel(entry.date)} · ${account.name}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Dismissible(
        key: ValueKey(entry.id),
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
        // No confirm dialog, same reasoning as expense delete: the swipe is
        // already deliberate, and undo is a real recovery, not just a warning.
        onDismissed: (_) => _deleteWithUndo(context, ref, title),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          onTap: () => showIncomeEditSheet(context, existing: entry),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.savings_outlined,
                  size: 18,
                  color: AppColors.primary,
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
                      subtitle,
                      style: TextStyle(fontSize: 12, color: palette.textDim),
                    ),
                  ],
                ),
              ),
              Text(
                '+${entry.amount.format(locale: 'en_IN')}',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteWithUndo(BuildContext context, WidgetRef ref, String title) {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ledgerRepositoryProvider);
    repo.delete(entry.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "$title"'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restore(entry),
          ),
        ),
      );
  }
}

/// Create (no [existing]) or edit an income entry: amount, date, source
/// label, account, note, repeat.
///
/// Full screen with a review step (2026-08-28 redesign), mirroring
/// `_TransferScreen` exactly — same top bar, same account-row and field
/// styling, same confirm-before-you-save pause — rather than the single-tap
/// bottom sheet this used to be.
Future<int?> showIncomeEditSheet(
  BuildContext context, {
  LedgerEntryRow? existing,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _IncomeEditScreen(existing: existing),
    ),
  );
}

/// Confirms one occurrence of a recurring income [template]: the screen
/// prefills from the template at [occurrence]'s date, the user reviews or
/// edits freely, and saving both logs the entry and advances the template's
/// schedule (`LedgerRepository.confirmIncome`) — the reviewed counterpart to
/// how a recurring expense confirms in one silent tap. Reached from the
/// Recurring screen's Income tab and from the "Add" notification action.
Future<int?> showIncomeConfirmSheet(
  BuildContext context, {
  required LedgerEntryRow template,
  required DateTime occurrence,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _IncomeEditScreen(
        confirmTemplate: template,
        confirmOccurrence: occurrence,
      ),
    ),
  );
}

/// The date field's starting value for [_IncomeEditScreen].
///
/// A due-or-past [confirmOccurrence] defaults to the scheduled day itself —
/// the normal confirm flow. An occurrence still in the future means this is
/// an early confirm (see `_MarkReceivedEarlyButton`): default to today, the
/// day it's actually being received, not the day it was scheduled for.
DateTime confirmSheetInitialDate({
  required DateTime? confirmOccurrence,
  required DateTime? existingDate,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  if (confirmOccurrence != null && !confirmOccurrence.isAfter(today)) {
    return confirmOccurrence;
  }
  return existingDate ?? today;
}

class _IncomeEditScreen extends ConsumerStatefulWidget {
  const _IncomeEditScreen({
    this.existing,
    this.confirmTemplate,
    this.confirmOccurrence,
  });
  final LedgerEntryRow? existing;

  /// Both set together — see [showIncomeConfirmSheet].
  final LedgerEntryRow? confirmTemplate;
  final DateTime? confirmOccurrence;

  @override
  ConsumerState<_IncomeEditScreen> createState() => _IncomeEditScreenState();
}

class _IncomeEditScreenState extends ConsumerState<_IncomeEditScreen> {
  /// What to prefill from — the template being confirmed, or an existing
  /// entry being edited. Never both; [showIncomeConfirmSheet] never passes
  /// an [existing] alongside a template.
  LedgerEntryRow? get _source => widget.confirmTemplate ?? widget.existing;

  bool get _isConfirming => widget.confirmTemplate != null;

  late String _amount = _source == null
      ? '0'
      : _source!.amount.major.toStringAsFixed(2);
  late final _sourceLabel = TextEditingController(
    text: _source?.sourceLabel ?? '',
  );
  final _sourceLabelFocusNode = FocusNode();
  late final _note = TextEditingController(text: _source?.note ?? '');
  final _noteFocusNode = FocusNode();
  late DateTime _date = confirmSheetInitialDate(
    confirmOccurrence: widget.confirmOccurrence,
    existingDate: widget.existing?.date,
  );
  late int? _accountId = _source?.accountId;
  // A confirmed occurrence is never itself a template — recurrence is the
  // template's own property, edited only when editing the template directly
  // (existing != null, not confirming).
  late Recurrence? _recurrence = _isConfirming
      ? null
      : widget.existing?.recurrence;
  late DateTime? _recurrenceEndDate = _isConfirming
      ? null
      : widget.existing?.recurrenceEndDate;
  bool _saving = false;

  /// Whether the on-screen numeric keypad (pinned to the bottom, same as
  /// Add Expense's) is showing. Off until the amount is explicitly tapped —
  /// never on by default, and always mutually exclusive with the source/note
  /// fields' OS keyboard.
  bool _amountActive = false;

  /// True once the form has passed validation and is showing the
  /// confirm-before-you-save summary instead of the editable fields — same
  /// pattern as `_TransferScreenState._reviewing`.
  bool _reviewing = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _sourceLabelFocusNode.addListener(() {
      if (_sourceLabelFocusNode.hasFocus) {
        setState(() => _amountActive = false);
      }
    });
    _noteFocusNode.addListener(() {
      if (_noteFocusNode.hasFocus) setState(() => _amountActive = false);
    });
  }

  void _activateAmount() {
    FocusScope.of(context).unfocus();
    setState(() => _amountActive = true);
  }

  void _dismissKeyboards() {
    FocusScope.of(context).unfocus();
    setState(() => _amountActive = false);
  }

  @override
  void dispose() {
    _sourceLabel.dispose();
    _sourceLabelFocusNode.dispose();
    _note.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  /// Same check [_save] used to run inline — extracted so the "Review
  /// income" step and the actual save both refuse the same bad input,
  /// instead of the review step waving through something the save would
  /// then reject.
  String? _validate() {
    final amount = Money.parse(_amount);
    if (amount.minor <= 0) return 'Enter an amount';
    return null;
  }

  void _proceedToReview() {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _reviewing = true;
      _amountActive = false;
    });
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    final amount = Money.parse(_amount);
    final repo = ref.read(ledgerRepositoryProvider);
    final sourceLabel = _sourceLabel.text.trim();
    final note = _note.text.trim();

    if (_isConfirming) {
      await repo.confirmIncome(
        widget.confirmTemplate!,
        widget.confirmOccurrence!,
        amount: amount,
        date: _date,
        accountId: _accountId,
        sourceLabel: sourceLabel.isEmpty ? null : sourceLabel,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      Navigator.of(context).pop(widget.confirmTemplate!.id);
      return;
    }

    // A changed schedule (or a template that never had a pointer, as a
    // pre-recurring row wouldn't) earns a fresh next-due date; an unchanged
    // one keeps its existing pointer rather than resetting it.
    final previous = widget.existing;
    final scheduleChanged =
        _recurrence != previous?.recurrence ||
        _recurrenceEndDate != previous?.recurrenceEndDate ||
        previous?.nextDueDate == null;
    final nextDue = _recurrence == null
        ? null
        : scheduleChanged
        ? firstDueDate(_date, _recurrence, endDate: _recurrenceEndDate)
        : previous!.nextDueDate;

    final int id;
    if (_isEdit) {
      final existing = widget.existing!;
      id = existing.id;
      if (existing.templateOnly || existing.isRecurring) {
        // Already its own template row, or a legacy pre-split shared-row
        // template (kept as-is — forward-only fix, see
        // `LedgerRepository.addIncomeWithRecurrence`'s doc comment) — safe
        // to edit every field on this same row.
        await repo.update(
          id,
          amount: amount,
          date: _date,
          accountId: _accountId,
          clearAccount: _accountId == null,
          sourceLabel: sourceLabel.isEmpty ? null : sourceLabel,
          note: note.isEmpty ? null : note,
          isRecurring: _recurrence != null && nextDue != null,
          recurrence: Value(_recurrence),
          nextDueDate: Value(nextDue),
          recurrenceEndDate: Value(_recurrenceEndDate),
        );
      } else {
        // A genuinely plain income entry — turning "Repeat" on here must
        // not turn this historical transaction into the shared template row.
        await repo.updateIncomeWithRecurrence(
          id: id,
          amount: amount,
          date: _date,
          accountId: _accountId,
          clearAccount: _accountId == null,
          sourceLabel: sourceLabel.isEmpty ? null : sourceLabel,
          note: note.isEmpty ? null : note,
          recurrence: _recurrence,
          nextDueDate: nextDue,
          recurrenceEndDate: _recurrenceEndDate,
        );
      }
    } else {
      id = await repo.addIncomeWithRecurrence(
        amount: amount,
        date: _date,
        accountId: _accountId,
        sourceLabel: sourceLabel.isEmpty ? null : sourceLabel,
        note: note.isEmpty ? null : note,
        recurrence: _recurrence,
        nextDueDate: nextDue,
        recurrenceEndDate: _recurrenceEndDate,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          "This can't be undone from here — you'd need to re-enter it.",
        ),
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
    );
    if (confirmed != true) return;
    await ref.read(ledgerRepositoryProvider).delete(widget.existing!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openAccountPicker(List<AccountRow> accounts) async {
    final chosen = await showAccountPickerSheet(
      context,
      accounts: accounts,
      selected: _accountId,
    );
    if (chosen == null || !mounted) return;
    setState(() => _accountId = chosen == noAccountChoice ? null : chosen);
  }

  Widget _topBar(BuildContext context, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: _reviewing ? 'Back' : 'Close',
            child: GestureDetector(
              onTap: () {
                if (_reviewing) {
                  setState(() => _reviewing = false);
                } else {
                  Navigator.of(context).pop();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.card,
                      border: Border.all(color: palette.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _reviewing ? Icons.arrow_back : Icons.close,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _reviewing
                ? 'Review income'
                : (_isConfirming
                      ? 'Confirm income'
                      : (_isEdit ? 'Edit income' : 'Add income')),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }

  Widget _accountRow({
    required IconData icon,
    required String label,
    required String accountName,
    required VoidCallback? onTap,
    required AppPalette palette,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.card2,
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: palette.textDim),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: palette.textDim),
                ),
                Text(
                  accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: palette.textDim),
        ],
      ),
    );
  }

  Widget _formScrollContent(
    BuildContext context,
    AppPalette palette,
    List<AccountRow> accounts,
    AccountRow? selectedAccount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accountRow(
          icon: Icons.savings_outlined,
          label: 'Account',
          accountName: selectedAccount?.name ?? 'None',
          onTap: () => _openAccountPicker(accounts),
          palette: palette,
        ),
        const SizedBox(height: AppSpacing.lg),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activateAmount,
          child: AmountDisplay(_amount, fontSize: 40),
        ),
        const SizedBox(height: AppSpacing.lg),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date',
              border: OutlineInputBorder(),
            ),
            child: Text(DateFormat('MMM d, yyyy').format(_date)),
          ),
        ),
        // Recurrence belongs to the template, not to one confirmed
        // occurrence — hidden while confirming.
        if (!_isConfirming) ...[
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: () => showRepeatPickerSheet(
              context,
              recurrence: _recurrence,
              endDate: _recurrenceEndDate,
              anchorDate: _date,
              onRecurrenceChanged: (r) => setState(() => _recurrence = r),
              onEndDateChanged: (d) => setState(() => _recurrenceEndDate = d),
            ),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Repeat',
                border: OutlineInputBorder(),
              ),
              child: Text(
                _recurrence == null
                    ? 'Does not repeat'
                    : recurrenceLabel(_recurrence!),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _sourceLabel,
          focusNode: _sourceLabelFocusNode,
          decoration: const InputDecoration(
            labelText: 'Source (optional)',
            hintText: 'e.g. Salary, Freelance',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _note,
          focusNode: _noteFocusNode,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  /// The bar pinned to the bottom of the screen (outside the scroll view,
  /// same structural spot as Add Expense's keypad+save bar): the numeric
  /// keypad — only while [_amountActive] — then the primary action.
  Widget _formBottomBar() {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _amountActive
              ? Column(
                  children: [
                    AmountKeypad(
                      onKey: (k) =>
                          setState(() => _amount = applyAmountKey(_amount, k)),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        PrimaryGradientButton(
          label: 'Review income',
          onPressed: _proceedToReview,
        ),
        if (_isEdit) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _confirmDelete,
              child: const Text(
                'Delete entry',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _reviewBody(AppPalette palette, AccountRow? selectedAccount) {
    final amount = Money.parse(_amount);
    final sourceLabel = _sourceLabel.text.trim();
    final note = _note.text.trim();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  sourceLabel.isEmpty ? 'Income' : sourceLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.arrow_forward, color: palette.textDim, size: 18),
              Expanded(
                child: Text(
                  selectedAccount?.name ?? 'No account',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              amount.format(locale: 'en_IN'),
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _reviewLine('Date', DateFormat('MMM d, yyyy').format(_date), palette),
          if (!_isConfirming && _recurrence != null)
            _reviewLine('Repeat', recurrenceLabel(_recurrence!), palette),
          if (note.isNotEmpty) _reviewLine('Note', note, palette),
        ],
      ),
    );
  }

  Widget _reviewBottomBar() {
    return PrimaryGradientButton(
      label: _saving ? 'Saving…' : 'Confirm income',
      semanticLabel: _saving ? 'Saving' : 'Confirm income',
      onPressed: _saving ? null : _save,
    );
  }

  Widget _reviewLine(String label, String value, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: palette.textDim, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <AccountRow>[];
    final selectedAccount = accounts
        .where((a) => a.id == _accountId)
        .cast<AccountRow?>()
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context, palette),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismissKeyboards,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: _reviewing
                      ? _reviewBody(palette, selectedAccount)
                      : _formScrollContent(
                          context,
                          palette,
                          accounts,
                          selectedAccount,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: _reviewing ? _reviewBottomBar() : _formBottomBar(),
            ),
          ],
        ),
      ),
    );
  }
}

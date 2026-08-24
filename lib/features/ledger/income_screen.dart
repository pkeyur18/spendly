import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/repeat_picker.dart';
import '../accounts/account_picker_sheet.dart';
import '../accounts/account_repository.dart';
import '../expenses/expense_repository.dart' show monthBounds;
import '../expenses/recurring_schedule.dart';
import '../expenses/widgets/expense_tile.dart' show relativeDayLabel;
import 'ledger_repository.dart';

/// Income (schema v15) — every entry, newest first, with this month's total
/// up top. Reached from Profile, same shape as Accounts/Recurring.
class IncomeScreen extends ConsumerWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This month',
                        style: TextStyle(fontSize: 13, color: palette.textDim),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (monthTotal.value ?? Money.zero).format(locale: 'en_IN'),
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
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _IncomeTile(entry: entries[i]),
                ),
              ),
            ],
          );
        },
      ),
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
/// label, account, note, repeat. Mirrors `_AccountEditSheet`'s shape.
Future<int?> showIncomeEditSheet(
  BuildContext context, {
  LedgerEntryRow? existing,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _IncomeEditSheet(existing: existing),
  );
}

/// Confirms one occurrence of a recurring income [template]: the sheet
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
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _IncomeEditSheet(
      confirmTemplate: template,
      confirmOccurrence: occurrence,
    ),
  );
}

class _IncomeEditSheet extends ConsumerStatefulWidget {
  const _IncomeEditSheet({
    this.existing,
    this.confirmTemplate,
    this.confirmOccurrence,
  });
  final LedgerEntryRow? existing;

  /// Both set together — see [showIncomeConfirmSheet].
  final LedgerEntryRow? confirmTemplate;
  final DateTime? confirmOccurrence;

  @override
  ConsumerState<_IncomeEditSheet> createState() => _IncomeEditSheetState();
}

class _IncomeEditSheetState extends ConsumerState<_IncomeEditSheet> {
  /// What to prefill from — the template being confirmed, or an existing
  /// entry being edited. Never both; [showIncomeConfirmSheet] never passes
  /// an [existing] alongside a template.
  LedgerEntryRow? get _source => widget.confirmTemplate ?? widget.existing;

  bool get _isConfirming => widget.confirmTemplate != null;

  late final _amount = TextEditingController(
    text: _source == null ? '' : _source!.amount.major.toStringAsFixed(2),
  );
  late final _sourceLabel = TextEditingController(
    text: _source?.sourceLabel ?? '',
  );
  late final _note = TextEditingController(text: _source?.note ?? '');
  late DateTime _date =
      widget.confirmOccurrence ?? widget.existing?.date ?? DateTime.now();
  late int? _accountId = _source?.accountId;
  // A confirmed occurrence is never itself a template — recurrence is the
  // template's own property, edited only when editing the template directly
  // (existing != null, not confirming).
  late Recurrence? _recurrence =
      _isConfirming ? null : widget.existing?.recurrence;
  late DateTime? _recurrenceEndDate =
      _isConfirming ? null : widget.existing?.recurrenceEndDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _amount.dispose();
    _sourceLabel.dispose();
    _note.dispose();
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

  Future<void> _save() async {
    final amount = Money.parse(_amount.text);
    if (amount.minor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    setState(() => _saving = true);
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
      id = widget.existing!.id;
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
      id = await repo.addIncome(
        amount: amount,
        date: _date,
        accountId: _accountId,
        sourceLabel: sourceLabel.isEmpty ? null : sourceLabel,
        note: note.isEmpty ? null : note,
        isRecurring: _recurrence != null && nextDue != null,
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

  Widget _saveButton() {
    return Semantics(
      button: true,
      label: _saving ? 'Saving' : 'Save income',
      child: GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          alignment: Alignment.center,
          child: Text(
            _saving ? 'Saving…' : 'Save',
            style: const TextStyle(
              fontFamily: 'Sora',
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isConfirming
                    ? 'Confirm income'
                    : (_isEdit ? 'Edit income' : 'Add income'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Amount leads and stands apart from the fields below it — the
              // one figure this whole sheet exists to capture. Sora, like
              // every monetary figure elsewhere in the app.
              TextField(
                controller: _amount,
                autofocus: !_isEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(DateFormat('MMM d, yyyy').format(_date)),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openAccountPicker(accounts),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Account',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          selectedAccount?.name ?? 'None',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
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
                    onEndDateChanged: (d) =>
                        setState(() => _recurrenceEndDate = d),
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
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Details',
                style: TextStyle(color: palette.textDim, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _sourceLabel,
                decoration: const InputDecoration(
                  labelText: 'Source (optional)',
                  hintText: 'e.g. Salary, Freelance',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _saveButton(),
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
          ),
        ),
      ),
    );
  }
}

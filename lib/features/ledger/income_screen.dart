import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../accounts/account_repository.dart';
import '../expenses/expense_repository.dart' show monthBounds;
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
/// label, account, note. Mirrors `_AccountEditSheet`'s shape.
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

class _IncomeEditSheet extends ConsumerStatefulWidget {
  const _IncomeEditSheet({this.existing});
  final LedgerEntryRow? existing;

  @override
  ConsumerState<_IncomeEditSheet> createState() => _IncomeEditSheetState();
}

class _IncomeEditSheetState extends ConsumerState<_IncomeEditSheet> {
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.amount.major.toStringAsFixed(2),
  );
  late final _sourceLabel = TextEditingController(
    text: widget.existing?.sourceLabel ?? '',
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late int? _accountId = widget.existing?.accountId;
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
      );
    } else {
      id = await repo.addIncome(
        amount: amount,
        date: _date,
        accountId: _accountId,
        sourceLabel: sourceLabel.isEmpty ? null : sourceLabel,
        note: note.isEmpty ? null : note,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _delete() async {
    await ref.read(ledgerRepositoryProvider).delete(widget.existing!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <AccountRow>[];
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
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
                _isEdit ? 'Edit income' : 'Add income',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _amount,
                autofocus: !_isEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sourceLabel,
                decoration: const InputDecoration(
                  labelText: 'Source (optional)',
                  hintText: 'e.g. Salary, Freelance',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('No account'),
                    selected: _accountId == null,
                    onSelected: (_) => setState(() => _accountId = null),
                  ),
                  for (final a in accounts)
                    ChoiceChip(
                      label: Text(a.name),
                      selected: _accountId == a.id,
                      onSelected: (_) => setState(() => _accountId = a.id),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _delete,
                    child: const Text('Delete'),
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

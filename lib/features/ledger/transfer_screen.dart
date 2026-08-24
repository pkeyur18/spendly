import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../accounts/account_picker_sheet.dart';
import '../accounts/account_repository.dart';
import 'ledger_repository.dart';

/// Move money between two of the user's own accounts (Phase 6). Neither
/// side is spend or income — see [LedgerEntries]'s `kind` doc comment.
Future<int?> showTransferEditSheet(
  BuildContext context, {
  LedgerEntryRow? existing,
  int? defaultFromAccountId,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _TransferEditSheet(
      existing: existing,
      defaultFromAccountId: defaultFromAccountId,
    ),
  );
}

class _TransferEditSheet extends ConsumerStatefulWidget {
  const _TransferEditSheet({this.existing, this.defaultFromAccountId});
  final LedgerEntryRow? existing;
  final int? defaultFromAccountId;

  @override
  ConsumerState<_TransferEditSheet> createState() => _TransferEditSheetState();
}

class _TransferEditSheetState extends ConsumerState<_TransferEditSheet> {
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.amount.major.toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late int? _fromAccountId =
      widget.existing?.accountId ?? widget.defaultFromAccountId;
  late int? _toAccountId = widget.existing?.counterAccountId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _amount.dispose();
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

  Future<void> _pickFrom(List<AccountRow> accounts) async {
    final chosen = await showAccountPickerSheet(
      context,
      accounts: accounts,
      selected: _fromAccountId,
      allowNone: false,
      exclude: _toAccountId == null ? const {} : {_toAccountId!},
      title: 'From account',
    );
    if (chosen == null || !mounted) return;
    setState(() => _fromAccountId = chosen);
  }

  Future<void> _pickTo(List<AccountRow> accounts) async {
    final chosen = await showAccountPickerSheet(
      context,
      accounts: accounts,
      selected: _toAccountId,
      allowNone: false,
      exclude: _fromAccountId == null ? const {} : {_fromAccountId!},
      title: 'To account',
    );
    if (chosen == null || !mounted) return;
    setState(() => _toAccountId = chosen);
  }

  Future<void> _save() async {
    final amount = Money.parse(_amount.text);
    if (amount.minor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    if (_fromAccountId == null || _toAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick both accounts')),
      );
      return;
    }
    if (_fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick two different accounts')),
      );
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(ledgerRepositoryProvider);
    final note = _note.text.trim();
    final int id;
    if (_isEdit) {
      id = widget.existing!.id;
      await repo.update(
        id,
        amount: amount,
        date: _date,
        accountId: _fromAccountId,
        counterAccountId: _toAccountId,
        note: note.isEmpty ? null : note,
      );
    } else {
      id = await repo.addTransfer(
        amount: amount,
        date: _date,
        fromAccountId: _fromAccountId!,
        toAccountId: _toAccountId!,
        note: note.isEmpty ? null : note,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this transfer?'),
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

  Widget _saveButton() {
    return Semantics(
      button: true,
      label: _saving ? 'Saving' : 'Save transfer',
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
    final fromAccount = accounts
        .where((a) => a.id == _fromAccountId)
        .cast<AccountRow?>()
        .firstOrNull;
    final toAccount = accounts
        .where((a) => a.id == _toAccountId)
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
                _isEdit ? 'Edit transfer' : 'Transfer money',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
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
                      onTap: () => _pickFrom(accounts),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'From',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          fromAccount?.name ?? 'Pick account',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Icon(Icons.arrow_forward, color: palette.textDim, size: 18),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTo(accounts),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'To',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          toAccount?.name ?? 'Pick account',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
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
                      'Delete transfer',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/buttons.dart';
import '../accounts/account_picker_sheet.dart';
import '../accounts/account_repository.dart';
import 'ledger_repository.dart';

/// Move money between two of the user's own accounts (Phase 6). Neither
/// side is spend or income — see [LedgerEntries]'s `kind` doc comment.
///
/// Full screen with a review step (2026-08-24 redesign) rather than a
/// bottom sheet — the one approved layout-pattern change in the glass
/// redesign, since a transfer benefits from a "did I get this right" pause
/// a single-tap sheet save doesn't offer.
Future<int?> showTransferEditSheet(
  BuildContext context, {
  LedgerEntryRow? existing,
  int? defaultFromAccountId,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TransferScreen(
        existing: existing,
        defaultFromAccountId: defaultFromAccountId,
      ),
    ),
  );
}

class _TransferScreen extends ConsumerStatefulWidget {
  const _TransferScreen({this.existing, this.defaultFromAccountId});
  final LedgerEntryRow? existing;
  final int? defaultFromAccountId;

  @override
  ConsumerState<_TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<_TransferScreen> {
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

  /// True once the form has passed validation and is showing the
  /// confirm-before-you-save summary instead of the editable fields.
  bool _reviewing = false;

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

  /// Same checks [_save] used to run inline — extracted so the "Review
  /// transfer" step (new) and the actual save both refuse the same bad
  /// input, instead of the review step waving through something the save
  /// would then reject.
  String? _validate() {
    final amount = Money.parse(_amount.text);
    if (amount.minor <= 0) return 'Enter an amount';
    if (_fromAccountId == null || _toAccountId == null) {
      return 'Pick both accounts';
    }
    if (_fromAccountId == _toAccountId) return 'Pick two different accounts';
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
    setState(() => _reviewing = true);
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
    final amount = Money.parse(_amount.text);
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
                ? 'Review transfer'
                : (_isEdit ? 'Edit transfer' : 'Transfer money'),
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
          if (onTap != null)
            Icon(Icons.chevron_right, color: palette.textDim),
        ],
      ),
    );
  }

  Widget _formBody(
    BuildContext context,
    AppPalette palette,
    List<AccountRow> accounts,
    AccountRow? fromAccount,
    AccountRow? toAccount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accountRow(
          icon: Icons.account_balance_outlined,
          label: 'From',
          accountName: fromAccount?.name ?? 'Pick account',
          onTap: () => _pickFrom(accounts),
          palette: palette,
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Icon(Icons.arrow_downward, color: palette.textDim, size: 18),
          ),
        ),
        _accountRow(
          icon: Icons.savings_outlined,
          label: 'To',
          accountName: toAccount?.name ?? 'Pick account',
          onTap: () => _pickTo(accounts),
          palette: palette,
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
        PrimaryGradientButton(
          label: 'Review transfer',
          onPressed: _proceedToReview,
        ),
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
    );
  }

  Widget _reviewBody(
    AppPalette palette,
    AccountRow? fromAccount,
    AccountRow? toAccount,
  ) {
    final amount = Money.parse(_amount.text);
    final note = _note.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      fromAccount?.name ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: palette.textDim, size: 18),
                  Expanded(
                    child: Text(
                      toAccount?.name ?? '',
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
              if (note.isNotEmpty) _reviewLine('Note', note, palette),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryGradientButton(
          label: _saving ? 'Saving…' : 'Confirm transfer',
          semanticLabel: _saving ? 'Saving' : 'Confirm transfer',
          onPressed: _saving ? null : _save,
        ),
      ],
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
    final fromAccount = accounts
        .where((a) => a.id == _fromAccountId)
        .cast<AccountRow?>()
        .firstOrNull;
    final toAccount = accounts
        .where((a) => a.id == _toAccountId)
        .cast<AccountRow?>()
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context, palette),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: _reviewing
                    ? _reviewBody(palette, fromAccount, toAccount)
                    : _formBody(
                        context,
                        palette,
                        accounts,
                        fromAccount,
                        toAccount,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

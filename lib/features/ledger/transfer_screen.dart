import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/amount_keypad.dart';
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
  late String _amount = widget.existing == null
      ? '0'
      : widget.existing!.amount.major.toStringAsFixed(2);
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  final _noteFocusNode = FocusNode();
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late int? _fromAccountId =
      widget.existing?.accountId ?? widget.defaultFromAccountId;
  late int? _toAccountId = widget.existing?.counterAccountId;
  bool _saving = false;

  /// Whether the on-screen numeric keypad (pinned to the bottom, same as
  /// Add Expense's) is showing. Off until the amount is explicitly tapped —
  /// never on by default, and always mutually exclusive with the note
  /// field's OS keyboard.
  bool _amountActive = false;

  /// True once the form has passed validation and is showing the
  /// confirm-before-you-save summary instead of the editable fields.
  bool _reviewing = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _noteFocusNode.addListener(() {
      if (_noteFocusNode.hasFocus) setState(() => _amountActive = false);
    });
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _activateAmount() {
    FocusScope.of(context).unfocus();
    setState(() => _amountActive = true);
  }

  void _dismissKeyboards() {
    FocusScope.of(context).unfocus();
    setState(() => _amountActive = false);
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
    final amount = Money.parse(_amount);
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
          if (onTap != null) Icon(Icons.chevron_right, color: palette.textDim),
        ],
      ),
    );
  }

  /// The scrollable part of the entry form — everything above the pinned
  /// keypad/button bar. No keyboard-triggering logic lives here beyond
  /// wiring taps/focus into [_amountActive].
  Widget _formScrollContent(
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
    final amount = Money.parse(_amount);
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
    );
  }

  Widget _reviewBottomBar() {
    return PrimaryGradientButton(
      label: _saving ? 'Saving…' : 'Confirm transfer',
      semanticLabel: _saving ? 'Saving' : 'Confirm transfer',
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismissKeyboards,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: _reviewing
                      ? _reviewBody(palette, fromAccount, toAccount)
                      : _formScrollContent(
                          context,
                          palette,
                          accounts,
                          fromAccount,
                          toAccount,
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

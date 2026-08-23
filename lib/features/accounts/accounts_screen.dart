import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../expenses/expense_repository.dart' show monthBounds;
import 'account_detail_screen.dart';
import 'account_repository.dart';

String _typeLabel(AccountType t) => switch (t) {
  AccountType.cash => 'Cash',
  AccountType.bank => 'Bank',
  AccountType.card => 'Card',
  AccountType.wallet => 'Wallet',
};

IconData _typeIcon(AccountType t) => switch (t) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.card => Icons.credit_card_outlined,
  AccountType.wallet => Icons.account_balance_wallet_outlined,
};

/// Accounts: where money is held or spent from (schema v12). Lists every
/// account with its spend this month; tap to rename/reclassify/archive.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allAccountsProvider);
    final (start, end) = monthBounds(DateTime.now());
    final totals = ref.watch(accountTotalsByRangeProvider((start, end)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Add account',
            onPressed: () => showAccountEditSheet(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load accounts.",
          onRetry: () => ref.invalidate(allAccountsProvider),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const EmptyView(
              icon: Icons.account_balance_wallet_outlined,
              message:
                  'No accounts yet. Add one to track spend by cash, bank, '
                  'card, or wallet.',
            );
          }
          final active = accounts.where((a) => !a.isArchived).toList();
          final archived = accounts.where((a) => a.isArchived).toList();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              for (final a in active)
                _AccountTile(account: a, spentThisMonth: totals.value?[a.id]),
              if (archived.isNotEmpty) ...[
                const SectionTitle('Archived'),
                for (final a in archived)
                  _AccountTile(account: a, spentThisMonth: null),
              ],
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.spentThisMonth});

  final AccountRow account;
  final Money? spentThisMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountDetailScreen(account: account),
          ),
        ),
        child: Opacity(
          opacity: account.isArchived ? 0.5 : 1,
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
                child: Icon(
                  _typeIcon(account.type),
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      account.isDefault
                          ? '${_typeLabel(account.type)} · Default'
                          : _typeLabel(account.type),
                      style: TextStyle(fontSize: 12, color: palette.textDim),
                    ),
                  ],
                ),
              ),
              if (spentThisMonth != null && spentThisMonth!.minor > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      spentThisMonth!.format(locale: 'en_IN'),
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'this month',
                      style: TextStyle(fontSize: 11, color: palette.textDim),
                    ),
                  ],
                ),
              if (!account.isArchived)
                IconButton(
                  tooltip: account.isDefault
                      ? 'Default account'
                      : 'Set as default',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    account.isDefault
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: account.isDefault
                        ? AppColors.accent
                        : palette.textDim,
                    size: 20,
                  ),
                  onPressed: account.isDefault
                      ? null
                      : () => ref
                            .read(accountRepositoryProvider)
                            .setDefault(account.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create (no [existing]) or edit an account: name, type, opening balance,
/// archive toggle. Resolves to the created/edited account's id (null if
/// dismissed without saving) — lets a caller like Quick Add's account picker
/// auto-select a freshly created account, same as the trip picker already
/// does for [showTagEditSheet].
Future<int?> showAccountEditSheet(
  BuildContext context, {
  AccountRow? existing,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _AccountEditSheet(existing: existing),
  );
}

class _AccountEditSheet extends ConsumerStatefulWidget {
  const _AccountEditSheet({this.existing});
  final AccountRow? existing;

  @override
  ConsumerState<_AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends ConsumerState<_AccountEditSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _openingBalance = TextEditingController(
    text: widget.existing == null
        ? ''
        : Money.fromMinor(
            widget.existing!.openingBalanceMinor,
          ).major.toStringAsFixed(2),
  );
  late AccountType _type = widget.existing?.type ?? AccountType.cash;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an account name')));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(accountRepositoryProvider);
    final balance = Money.parse(_openingBalance.text);
    final int id;
    if (_isEdit) {
      id = widget.existing!.id;
      await repo.update(id, name: name, type: _type, openingBalance: balance);
    } else {
      id = await repo.create(name: name, type: _type, openingBalance: balance);
    }
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _archive(bool archived) async {
    final id = widget.existing!.id;
    await ref.read(accountRepositoryProvider).setArchived(id, archived);
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit account' : 'Add account',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. HDFC Bank, Cash',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final t in AccountType.values)
                  ChoiceChip(
                    label: Text(_typeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _openingBalance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Opening balance',
                prefixText: '₹ ',
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
                  onPressed: () => _archive(!widget.existing!.isArchived),
                  child: Text(
                    widget.existing!.isArchived
                        ? 'Unarchive'
                        : 'Archive this account',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

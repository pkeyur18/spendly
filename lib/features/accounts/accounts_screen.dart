import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/category_glyph.dart';
import '../../core/widgets/icon_color_picker.dart';
import '../expenses/expense_repository.dart' show monthBounds;
import 'account_detail_screen.dart';
import 'account_repository.dart';

/// Curated emoji set for a custom account type's icon (schema v20) — themed
/// for what an account IS (a loan, a goal, a fund), not what it's spent on
/// like Categories' set is. No emoji-keyboard dependency, same reasoning as
/// `category_edit_sheet.dart`'s own list.
const _accountIconChoices = [
  '🏦',
  '💳',
  '💰',
  '🪙',
  '📈',
  '📉',
  '🏠',
  '🚗',
  '🎓',
  '🛡️',
  '💼',
  '👴',
  '🎯',
  '🔑',
  '📦',
  '🌱',
  '♻️',
  '🧾',
  '💸',
  '🏆',
  '🎁',
  '👶',
  '🐷',
  '⚡',
  '🏥',
  '✈️',
  '📱',
  '🌍',
  '🔒',
  '🏢',
];

/// Section-heading label per type — fixed per built-in type, or a single
/// shared "Custom" bucket for every custom-type account regardless of its
/// own individual name (see [accountTypeLabel] for that).
String _typeLabel(AccountType t) => switch (t) {
  AccountType.cash => 'Cash',
  AccountType.bank => 'Bank',
  AccountType.card => 'Card',
  AccountType.wallet => 'Wallet',
  AccountType.custom => 'Custom',
};

/// Fallback Material icon per built-in type. Never actually shown for a
/// custom account — [_AccountTile] renders its own emoji/color instead —
/// but every enum value still needs a case for [AccountType.values] to stay
/// exhaustive.
IconData _typeIcon(AccountType t) => switch (t) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.card => Icons.credit_card_outlined,
  AccountType.wallet => Icons.account_balance_wallet_outlined,
  AccountType.custom => Icons.category_outlined,
};

/// The label to show for one specific account — unlike [_typeLabel], this
/// reads the account's own [AccountRow.customTypeName] for a custom account
/// instead of collapsing every custom account to the same "Custom" text, so
/// individual accounts don't lose that detail just because they share a
/// section heading.
String accountTypeLabel(AccountRow account) {
  if (account.type != AccountType.custom) return _typeLabel(account.type);
  final name = account.customTypeName;
  return name != null && name.isNotEmpty ? name : 'Custom';
}

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
              for (final type in AccountType.values)
                if (active.any((a) => a.type == type)) ...[
                  SectionTitle(_typeLabel(type)),
                  for (final a in active.where((a) => a.type == type))
                    _AccountTile(
                      account: a,
                      spentThisMonth: totals.value?[a.id],
                    ),
                ],
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
              _AccountTypeIcon(account: account),
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
                          ? '${accountTypeLabel(account)} · Default'
                          : accountTypeLabel(account),
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

/// The icon box on an account tile — a built-in type's fixed Material icon
/// on the app's primary color, or a custom account's own emoji on its own
/// color (falling back to the primary-color box if either is somehow unset,
/// which the edit sheet never actually leaves happen).
class _AccountTypeIcon extends StatelessWidget {
  const _AccountTypeIcon({required this.account});

  final AccountRow account;

  @override
  Widget build(BuildContext context) {
    final icon = account.customTypeIcon;
    final colorValue = account.customTypeColorValue;
    if (account.type == AccountType.custom && icon != null && colorValue != null) {
      final color = Color(colorValue);
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.icon),
        ),
        alignment: Alignment.center,
        child: CategoryGlyph(icon, size: 20),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.icon),
      ),
      alignment: Alignment.center,
      child: Icon(_typeIcon(account.type), size: 20, color: AppColors.primary),
    );
  }
}

/// Create (no [existing]) or edit an account: name, type, opening balance,
/// archive toggle. Resolves to the created/edited account's id and whether
/// this call archived it (null if dismissed without saving) — the id lets a
/// caller like Quick Add's account picker auto-select a freshly created
/// account, same as the trip picker already does for [showTagEditSheet];
/// `archived` lets the account detail screen tell "saved, stay here" apart
/// from "archived, nothing left to show".
Future<({int id, bool archived})?> showAccountEditSheet(
  BuildContext context, {
  AccountRow? existing,
}) {
  return showModalBottomSheet<({int id, bool archived})>(
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
  // Always the magnitude, regardless of sign — a liability's stored balance
  // is negative, but the field itself is where you type "10,00,000", not
  // "-10,00,000".
  late final _openingBalance = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.openingBalance.abs().major.toStringAsFixed(2),
  );
  late AccountType _type = widget.existing?.type ?? AccountType.cash;
  late bool _includeInNetWorth = widget.existing?.includeInNetWorth ?? true;
  late bool _isLiability = widget.existing?.isLiability ?? false;
  late final _customTypeName = TextEditingController(
    text: widget.existing?.customTypeName ?? '',
  );
  late String _customTypeIcon =
      widget.existing?.customTypeIcon ?? _accountIconChoices.first;
  late int _customTypeColorValue =
      widget.existing?.customTypeColorValue ??
      AppColors.swatchPalette.first.toARGB32();
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    _customTypeName.dispose();
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
    final isCustom = _type == AccountType.custom;
    final customName = isCustom ? _customTypeName.text.trim() : null;
    if (isCustom && (customName == null || customName.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name for this custom type')),
      );
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(accountRepositoryProvider);
    // The field is always a magnitude; nature decides the stored sign, so
    // toggling it re-signs the balance on save regardless of what was typed.
    final magnitude = Money.parse(_openingBalance.text).abs();
    final balance = _isLiability ? magnitude * -1 : magnitude;
    final customIcon = isCustom ? _customTypeIcon : null;
    final customColor = isCustom ? _customTypeColorValue : null;
    final int id;
    if (_isEdit) {
      id = widget.existing!.id;
      await repo.update(
        id,
        name: name,
        type: _type,
        openingBalance: balance,
        includeInNetWorth: _includeInNetWorth,
        isLiability: _isLiability,
        updateCustomType: true,
        customTypeName: customName,
        customTypeIcon: customIcon,
        customTypeColorValue: customColor,
      );
    } else {
      id = await repo.create(
        name: name,
        type: _type,
        openingBalance: balance,
        includeInNetWorth: _includeInNetWorth,
        isLiability: _isLiability,
        customTypeName: customName,
        customTypeIcon: customIcon,
        customTypeColorValue: customColor,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop((id: id, archived: false));
  }

  Future<void> _archive(bool archived) async {
    final id = widget.existing!.id;
    await ref.read(accountRepositoryProvider).setArchived(id, archived);
    if (!mounted) return;
    Navigator.of(context).pop((id: id, archived: archived));
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
            if (_type == AccountType.custom) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _customTypeName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Type name',
                  hintText: 'e.g. Loan, Gold, Investment',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              IconColorPicker(
                iconChoices: _accountIconChoices,
                selectedIcon: _customTypeIcon,
                onIconChanged: (v) => setState(() => _customTypeIcon = v),
                colorChoices: AppColors.swatchPalette,
                selectedColor: _customTypeColorValue,
                onColorChanged: (v) =>
                    setState(() => _customTypeColorValue = v),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This is money I owe'),
              subtitle: const Text(
                'Loan, credit card debt — opening balance below is stored '
                'as a negative running balance',
              ),
              value: _isLiability,
              onChanged: (v) => setState(() => _isLiability = v),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _openingBalance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _isLiability ? 'Amount owed' : 'Opening balance',
                prefixText: '₹ ',
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Count toward net worth total'),
              subtitle: const Text(
                "Include this account in the home screen's balance",
              ),
              value: _includeInNetWorth,
              onChanged: (v) => setState(() => _includeInNetWorth = v),
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

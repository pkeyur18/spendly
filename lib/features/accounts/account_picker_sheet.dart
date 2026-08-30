import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass.dart';

/// Sentinel distinguishing an explicit "No account" pick from a dismissed
/// sheet, when [showAccountPickerSheet] is called with `allowNone: true`.
const noAccountChoice = -1;

/// One picker sheet shared by every "pick an account" moment outside Quick
/// Add (which keeps its own copy — it alone needs a "+ New account"
/// shortcut inline). Returns the picked account id, [noAccountChoice] for an
/// explicit "No account" pick, or null if dismissed without choosing.
///
/// Frequent-first (schema v23): when at least one of [accounts] has
/// [AccountRow.isFrequent] set, the sheet opens showing only those (plus
/// [selected]'s own account, if any, so an existing non-frequent pick is
/// never hidden) with a trailing "See all accounts" row that expands it to
/// the full list in place. With no frequent accounts, this is unchanged from
/// before — every account shows straight away.
Future<int?> showAccountPickerSheet(
  BuildContext context, {
  required List<AccountRow> accounts,
  required int? selected,
  bool allowNone = true,
  Set<int> exclude = const {},
  String title = 'Account',
}) {
  final available = accounts.where((a) => !exclude.contains(a.id)).toList();
  final frequent = available.where((a) => a.isFrequent).toList();
  var showAll = frequent.isEmpty;
  return showGlassSheet<int>(
    context,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedAccount = selected == null
                ? null
                : available
                      .where((a) => a.id == selected)
                      .cast<AccountRow?>()
                      .firstOrNull;
            final options = showAll
                ? available
                : [
                    ...frequent,
                    if (selectedAccount != null && !selectedAccount.isFrequent)
                      selectedAccount,
                  ];
            final showSeeAll = !showAll && options.length < available.length;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(title),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount:
                        options.length +
                        (allowNone ? 1 : 0) +
                        (showSeeAll ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (allowNone && i == 0) {
                        return ListTile(
                          leading: const Icon(Icons.close, size: 20),
                          title: const Text('No account'),
                          trailing: selected == null
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.primary,
                                  size: 18,
                                )
                              : null,
                          onTap: () => Navigator.of(
                            sheetContext,
                          ).pop<int?>(noAccountChoice),
                        );
                      }
                      final optionIndex = allowNone ? i - 1 : i;
                      if (optionIndex >= options.length) {
                        return ListTile(
                          leading: const Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                          ),
                          title: const Text('See all accounts'),
                          onTap: () => setSheetState(() => showAll = true),
                        );
                      }
                      final a = options[optionIndex];
                      return ListTile(
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 20,
                        ),
                        title: Text(a.name),
                        trailing: a.id == selected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                                size: 18,
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop<int?>(a.id),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/theme/tokens.dart';

/// Sentinel distinguishing an explicit "No account" pick from a dismissed
/// sheet, when [showAccountPickerSheet] is called with `allowNone: true`.
const noAccountChoice = -1;

/// One picker sheet shared by every "pick an account" moment outside Quick
/// Add (which keeps its own copy — it alone needs a "+ New account"
/// shortcut inline). Returns the picked account id, [noAccountChoice] for an
/// explicit "No account" pick, or null if dismissed without choosing.
Future<int?> showAccountPickerSheet(
  BuildContext context, {
  required List<AccountRow> accounts,
  required int? selected,
  bool allowNone = true,
  Set<int> exclude = const {},
  String title = 'Account',
}) {
  final options = accounts.where((a) => !exclude.contains(a.id)).toList();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(title),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length + (allowNone ? 1 : 0),
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
                      onTap: () =>
                          Navigator.of(sheetContext).pop<int?>(noAccountChoice),
                    );
                  }
                  final a = options[allowNone ? i - 1 : i];
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
        ),
      ),
    ),
  );
}

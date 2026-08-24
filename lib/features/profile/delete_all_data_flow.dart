import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../backup/backup_restore_screen.dart' show performManualBackup;
import 'profile_provider.dart';

enum _BackupChoice { backUp, skip, cancel }

/// FR-58: "Delete all data" — gated behind a backup-first prompt so a user
/// can't lose data by accident. Moved here (from the old SettingsScreen) as
/// part of folding destructive reset into Profile's "Account actions".
Future<void> runDeleteAllDataFlow(BuildContext context, WidgetRef ref) async {
  final choice = await showDialog<_BackupChoice>(
    context: context,
    builder: (_) => const _BackupFirstDialog(),
  );
  if (choice == null || choice == _BackupChoice.cancel) return;
  if (!context.mounted) return;

  if (choice == _BackupChoice.backUp) {
    await performManualBackup(context, ref);
    if (!context.mounted) return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const ResetConfirmDialog(),
  );
  if (confirmed != true) return;

  await ref.read(databaseProvider).resetToDefaults();
  ref.invalidate(profileProvider);

  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('App has been reset')));
}

class _BackupFirstDialog extends StatelessWidget {
  const _BackupFirstDialog();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.boldDialogActions(context),
      child: AlertDialog(
        title: const Text('Back up your data first?'),
        content: const Text(
          "Deleting all data can't be undone. We recommend backing up first "
          'so you can restore it later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_BackupChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_BackupChoice.skip),
            child: const Text('Continue without backing up'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_BackupChoice.backUp),
            child: const Text('Back up now'),
          ),
        ],
      ),
    );
  }
}

/// Type-to-confirm gate before the destructive reset — pops `true` only once
/// the typed text matches [_confirmWord].
class ResetConfirmDialog extends StatefulWidget {
  const ResetConfirmDialog({super.key});

  static const _confirmWord = 'DELETE';

  @override
  State<ResetConfirmDialog> createState() => _ResetConfirmDialogState();
}

class _ResetConfirmDialogState extends State<ResetConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.boldDialogActions(context),
      child: AlertDialog(
        title: const Text('Delete all data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently erases all expenses, budgets, categories, and '
              'settings on this device. Backups are not affected. This cannot '
              'be undone.',
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Type ${ResetConfirmDialog._confirmWord} to confirm.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Confirmation'),
              onChanged: (v) => setState(
                () => _matches = v == ResetConfirmDialog._confirmWord,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete all data'),
          ),
        ],
      ),
    );
  }
}

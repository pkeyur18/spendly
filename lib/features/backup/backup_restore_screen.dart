import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import 'backup_export.dart';
import 'backup_providers.dart';
import 'local_auto_backup.dart';
import 'restore_screen.dart';

/// Backup & Restore (FR-33..43) — prototype phone 9.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(lastBackupStatusProvider);
    final autoBackupAsync = ref.watch(autoBackupSettingsProvider);

    if (statusAsync.isLoading || autoBackupAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup & Restore')),
        body: const LoadingView(),
      );
    }
    if (statusAsync.hasError || autoBackupAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup & Restore')),
        body: ErrorView(
          message: 'Couldn\'t load backup settings.',
          onRetry: () {
            ref.invalidate(lastBackupStatusProvider);
            ref.invalidate(autoBackupSettingsProvider);
          },
        ),
      );
    }
    final status = statusAsync.value;
    final autoBackup = autoBackupAsync.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          40,
        ),
        children: [
          _StatusCard(status: status),
          const SectionTitle('Automatic backup'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Auto backup',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Creates a new backup on a schedule',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).extension<AppPalette>()!.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: autoBackup?.enabled ?? false,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => ref
                          .read(autoBackupSettingsProvider.notifier)
                          .setEnabled(v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (final freq in BackupFrequency.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: _FreqChip(
                            label: _freqLabel(freq),
                            selected: autoBackup?.frequency == freq,
                            onTap: () => ref
                                .read(autoBackupSettingsProvider.notifier)
                                .setFrequency(freq),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('Manual backup'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save a full copy of your expenses, categories, and budgets right now.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).extension<AppPalette>()!.textDim,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: _busy ? 'Backing up…' : 'Back up now',
                  onTap: _busy ? null : _backUpNow,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlineButton(
                  label: 'Restore from a backup file',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RestoreScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle("What's included"),
          AppCard(
            child: Column(
              children: const [
                _PreviewRow('Expenses', '✓ All transactions'),
                _PreviewRow('Categories', '✓ Custom + defaults'),
                _PreviewRow('Budgets', '✓ Overall + per-category'),
                _PreviewRow('Settings', '✓ Theme, currency'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _freqLabel(BackupFrequency f) => switch (f) {
    BackupFrequency.daily => 'Daily',
    BackupFrequency.weekly => 'Weekly',
    BackupFrequency.monthly => 'Monthly',
  };

  Future<void> _backUpNow() async {
    final password = await _askOptionalPassword(context);
    if (password == null || !mounted) return; // dialog dismissed/cancelled
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(backupRepositoryProvider);
      final settings = ref.read(settingsRepositoryProvider);
      await shareBackupFile(
        repo,
        settings,
        password: password.isEmpty ? null : password,
      );
      ref.invalidate(lastBackupStatusProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Backup created')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns null if the user cancels; otherwise the password to encrypt
  /// with, or '' for no password (optional password protection, PRD open Q6).
  Future<String?> _askOptionalPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Back up now'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Optionally protect this backup with a password.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Back up'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final BackupStatus? status;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final at = status?.lastBackupAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const Text('☁️', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  at == null ? 'No backup yet' : 'Your data is backed up',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            at == null
                ? 'Back up now to protect your data.'
                : 'Last backup: ${DateFormat.yMMMd().add_jm().format(at)} · '
                      '${_formatSize(status?.lastBackupSizeBytes)}',
            style: TextStyle(fontSize: 12, color: palette.textDim),
          ),
          if (at != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Protected',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FreqChip extends StatelessWidget {
  const _FreqChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : palette.card2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : palette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : palette.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient CTA matching the prototype's `.btn-save` — shared with
/// `restore_screen.dart`.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: onTap == null ? null : AppColors.brandGradient,
            color: onTap == null
                ? Theme.of(context).disabledColor.withValues(alpha: 0.2)
                : null,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
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
}

/// Outline CTA matching the prototype's `.btn-outline` — shared with
/// `restore_screen.dart`.
class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: palette.textDim)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

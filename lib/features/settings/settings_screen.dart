import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../backup/backup_restore_screen.dart';
import '../profile/profile_provider.dart';
import '../profile/profile_screen.dart';
import 'theme_mode_provider.dart';

/// Settings — replaces the Sprint-4 stub. Currency/notifications rows are
/// deliberately not stubbed here; they aren't assigned a sprint yet.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeAsync = ref.watch(themeModeProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: themeModeAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Couldn\'t load settings.',
          onRetry: () => ref.invalidate(themeModeProvider),
        ),
        data: (themeMode) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            40,
          ),
          children: [
            _SettingsTile(
              icon: Icons.person_outline,
              title: 'Profile',
              subtitle: (profileAsync.value?.name.isNotEmpty ?? false)
                  ? profileAsync.value!.name
                  : 'Add your details',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SettingsTile(
              icon: Icons.brightness_6_outlined,
              title: 'Theme',
              subtitle: _themeLabel(themeMode),
              onTap: () => _cycleTheme(ref),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SettingsTile(
              icon: Icons.cloud_outlined,
              title: 'Backup & Restore',
              subtitle: 'Back up your data, restore from a file',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
              ),
            ),
            const SectionTitle('Danger zone'),
            _SettingsTile(
              icon: Icons.delete_forever_outlined,
              iconColor: AppColors.red,
              title: 'Reset App',
              subtitle: 'Erase all expenses, budgets, categories, settings',
              onTap: () => _showResetDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResetDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ResetConfirmDialog(),
    );
    if (confirmed != true) return;

    await ref.read(databaseProvider).resetToDefaults();
    ref.invalidate(themeModeProvider);
    ref.invalidate(profileProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App has been reset')));
  }

  String _themeLabel(ThemeMode m) => switch (m) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  void _cycleTheme(WidgetRef ref) {
    final current = ref.read(themeModeProvider).value ?? ThemeMode.system;
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(current) + 1) % order.length];
    ref.read(themeModeProvider.notifier).setMode(next);
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: palette.textDim),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Type-to-confirm gate before the destructive reset — pops `true` only once
/// the typed text matches [_confirmWord].
class _ResetConfirmDialog extends StatefulWidget {
  const _ResetConfirmDialog();

  static const _confirmWord = 'DELETE';

  @override
  State<_ResetConfirmDialog> createState() => _ResetConfirmDialogState();
}

class _ResetConfirmDialogState extends State<_ResetConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset App'),
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
            'Type ${_ResetConfirmDialog._confirmWord} to confirm.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Confirmation'),
            onChanged: (v) => setState(
              () => _matches = v == _ResetConfirmDialog._confirmWord,
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
          child: const Text('Reset App'),
        ),
      ],
    );
  }
}

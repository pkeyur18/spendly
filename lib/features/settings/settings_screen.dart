import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_state_views.dart';
import '../backup/backup_restore_screen.dart';
import 'theme_mode_provider.dart';

/// Settings — replaces the Sprint-4 stub. Currency/notifications rows are
/// deliberately not stubbed here; they aren't assigned a sprint yet.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeAsync = ref.watch(themeModeProvider);

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
          ],
        ),
      ),
    );
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
              Icon(icon, color: AppColors.primary),
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

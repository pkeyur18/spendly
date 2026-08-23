import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../backup/backup_restore_screen.dart';
import '../settings/theme_mode_provider.dart';
import 'avatar.dart';
import 'avatar_picker_screen.dart';
import 'delete_all_data_flow.dart';
import 'edit_profile_screen.dart';
import 'lifetime_stats.dart';
import 'profile_provider.dart';
import '../expenses/recurring_screen.dart';
import '../recap/monthly_recap_screen.dart';

/// Profile (FR-51, FR-57) — prototype phone 10. The account/settings hub:
/// avatar, lifetime stats, and links to Edit Profile, Avatar Picker, Theme,
/// Currency, Backup & Restore, and the backup-gated Delete-all-data action.
/// Replaces the old bare SettingsScreen as the bottom-nav gear destination —
/// the PRD screen list has no separate "Settings" screen, and the prototype's
/// gear icon opens this screen directly.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final themeModeAsync = ref.watch(themeModeProvider);
    final stats = ref.watch(lifetimeStatsProvider).value ?? LifetimeStats.zero;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Couldn\'t load profile.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (profile) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            40,
          ),
          children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ProfileAvatar(
                        name: profile.name,
                        photoBytes: profile.photoBytes,
                        avatarColorIndex: profile.avatarColorIndex,
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: _EditBadge(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AvatarPickerScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (profile.email.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      profile.email,
                      style: TextStyle(fontSize: 12.5, color: palette.textDim),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                _StatCard(value: stats.monthsTracked, label: 'months tracked'),
                const SizedBox(width: AppSpacing.sm),
                _StatCard(
                  value: stats.expensesLogged,
                  label: 'expenses logged',
                ),
                const SizedBox(width: AppSpacing.sm),
                _StatCard(value: stats.categoriesUsed, label: 'categories'),
              ],
            ),
            const SectionTitle('Account'),
            _MenuGroup(
              children: [
                _MenuRow(
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  subtitle: 'Name, phone, email',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
                ),
                _MenuRow(
                  icon: Icons.image_outlined,
                  title: 'Change photo / avatar',
                  subtitle: 'Upload or choose a style',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AvatarPickerScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SectionTitle('Preferences'),
            _MenuGroup(
              children: [
                _MenuRow(
                  icon: Icons.brightness_6_outlined,
                  title: 'Theme',
                  subtitle: _themeLabel(
                    themeModeAsync.value ?? ThemeMode.system,
                  ),
                  onTap: () => _openThemePicker(
                    context,
                    ref,
                    themeModeAsync.value ?? ThemeMode.system,
                  ),
                ),
                const _MenuRow(
                  icon: Icons.currency_rupee,
                  title: 'Currency',
                  subtitle: 'Indian Rupee (₹)',
                  onTap: null, // read-only: multi-currency is v2, PROGRESS.md
                ),
                _MenuRow(
                  icon: Icons.cloud_outlined,
                  title: 'Backup & Restore',
                  subtitle: 'Back up your data, restore from a file',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BackupRestoreScreen(),
                    ),
                  ),
                ),
                _MenuRow(
                  icon: Icons.repeat_rounded,
                  title: 'Recurring expenses',
                  subtitle: 'Rent, EMIs and subscriptions you track',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecurringScreen()),
                  ),
                ),
                _MenuRow(
                  icon: Icons.calendar_month_outlined,
                  title: 'Monthly recap',
                  subtitle: "Revisit last month's summary",
                  onTap: () {
                    final now = DateTime.now();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MonthlyRecapScreen(
                          month: DateTime(now.year, now.month - 1, 1),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SectionTitle('Account actions'),
            _MenuGroup(
              children: [
                _MenuRow(
                  icon: Icons.delete_outline,
                  title: 'Delete all data',
                  subtitle: 'Permanent — back up first',
                  danger: true,
                  onTap: () => runDeleteAllDataFlow(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _themeLabel(ThemeMode m) => switch (m) {
    ThemeMode.system => 'System default',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  Future<void> _openThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          title: const Text('Theme'),
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          content: RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (value) {
              if (value == null) return;
              ref.read(themeModeProvider.notifier).setMode(value);
              Navigator.of(dialogContext).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: mode,
                    title: Text(_themeLabel(mode)),
                    activeColor: AppColors.primary,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Semantics(
      button: true,
      label: 'Change photo or avatar',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.card,
            border: Border.all(color: palette.textDim.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.edit, size: 14),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: palette.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grouped card of [_MenuRow]s, hairline-divided (the prototype's
/// `.menu-list`).
class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, color: palette.line),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final tint = danger ? AppColors.red : AppColors.primary;
    final row = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: danger ? AppColors.red : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: palette.textDim),
                ),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: palette.textDim),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

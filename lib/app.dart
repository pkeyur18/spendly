import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notify/notifications.dart';
import 'core/theme/app_theme.dart';
import 'features/backup/backup_providers.dart';
import 'features/home/home_screen.dart';
import 'features/settings/theme_mode_provider.dart';

class SpendlyApp extends ConsumerStatefulWidget {
  const SpendlyApp({super.key});

  @override
  ConsumerState<SpendlyApp> createState() => _SpendlyAppState();
}

/// Runs the auto-backup due-check (FR-37) on cold start and every app
/// resume — see `local_auto_backup.dart` for why this isn't a true OS
/// background schedule.
class _SpendlyAppState extends ConsumerState<SpendlyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(autoBackupCheckProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoBackupCheckProvider); // fires the cold-start check
    // Falls back to system while the persisted value loads.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp(
      title: 'Spendly',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}

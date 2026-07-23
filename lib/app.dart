import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'core/notify/notifications.dart';
import 'core/theme/app_theme.dart';
import 'features/backup/backup_providers.dart';
import 'features/expenses/quick_add_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/theme_mode_provider.dart';
import 'features/widgets/widget_refresh.dart';

class SpendlyApp extends ConsumerStatefulWidget {
  const SpendlyApp({super.key});

  @override
  ConsumerState<SpendlyApp> createState() => _SpendlyAppState();
}

/// On cold start and every resume, runs the auto-backup due-check (FR-37, see
/// `local_auto_backup.dart`) and refreshes the widget snapshot (FR-29 — the
/// catch-all for changes that don't route through Quick Add, e.g. a restore).
/// Also routes widget quick-add taps into Quick Add (FR-3).
class _SpendlyAppState extends ConsumerState<SpendlyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A widget tap can cold-launch the app; handle both that and taps while
    // running.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
    HomeWidget.widgetClicked.listen(_handleWidgetUri);
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshWidgets(ref));
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
      refreshWidgets(ref);
    }
  }

  /// Widget quick-add deep link: `spendly://quickadd?category=<id>` opens
  /// Quick Add with that category preselected.
  void _handleWidgetUri(Uri? uri) {
    if (uri == null || uri.host != 'quickadd') return;
    final id = int.tryParse(uri.queryParameters['category'] ?? '');
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => QuickAddScreen(initialCategoryId: id)),
    );
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

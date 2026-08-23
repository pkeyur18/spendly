import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'core/notify/notifications.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/async_state_views.dart';
import 'features/backup/backup_providers.dart';
import 'features/budgets/budget_nudge_provider.dart';
import 'features/expenses/quick_add_screen.dart';
import 'features/home/app_shell.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/profile/profile_provider.dart';
import 'features/recap/recap_providers.dart';
import 'features/settings/theme_mode_provider.dart';
import 'features/widgets/widget_refresh.dart';
import 'features/widgets/widget_snapshot.dart' show widgetAppGroupId;

class SpendlyApp extends ConsumerStatefulWidget {
  const SpendlyApp({super.key});

  @override
  ConsumerState<SpendlyApp> createState() => _SpendlyAppState();
}

/// On cold start and every resume, runs the auto-backup due-check (FR-37, see
/// `local_auto_backup.dart`) and refreshes the widget snapshot (FR-29 — the
/// catch-all for changes that don't route through Quick Add, e.g. a restore).
/// Also routes widget quick-add taps into Quick Add (FR-3).
class _SpendlyAppState extends ConsumerState<SpendlyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Must be set before any other HomeWidget call (iOS throws otherwise).
    HomeWidget.setAppGroupId(widgetAppGroupId).then((_) {
      // A widget tap can cold-launch the app; handle both that and taps
      // while running.
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
    });
    HomeWidget.widgetClicked.listen(_handleWidgetUri);
    ref.read(widgetRefreshHookProvider); // arms the on-write refresh hook once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(refreshWidgetsActionProvider)();
      _initNotifications();
    });
  }

  /// Deferred off `main()`'s cold-start path (Sprint 7 perf fix) — see
  /// main.dart. Un-awaited: nothing in the first frame depends on this
  /// completing.
  Future<void> _initNotifications() async {
    final notifications = ref.read(notificationServiceProvider);
    await notifications.init();
    await notifications.scheduleMonthlyReport();
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
      ref.invalidate(monthlyRecapCheckProvider);
      ref.invalidate(budgetNudgeCheckProvider);
      ref.read(refreshWidgetsActionProvider)();
    }
  }

  /// Widget quick-add deep link: `spendly://quickadd?category=<id>` opens
  /// Quick Add with that category preselected.
  void _handleWidgetUri(Uri? uri) {
    if (uri == null || uri.host != 'quickadd') return;
    final id = int.tryParse(uri.queryParameters['category'] ?? '');
    final context = appNavigatorKey.currentContext;
    if (context != null) openQuickAddScreen(context, initialCategoryId: id);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoBackupCheckProvider); // fires the cold-start check
    ref.watch(
      monthlyRecapCheckProvider,
    ); // fires the once-per-month recap check
    ref.watch(
      budgetNudgeCheckProvider,
    ); // fires the once-per-month budget nudge check
    // Falls back to system while the persisted value loads.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final profileAsync = ref.watch(profileProvider);

    return MaterialApp(
      title: 'Spendly',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Crossfades light/dark colors on a theme switch — the prototype's one
      // intentional motion rule (`body { transition: background .4s ease,
      // color .4s ease }`). No other animation was designed, so this is the
      // only motion this sprint adds (Sprint 7).
      builder: (context, child) => AnimatedTheme(
        data: Theme.of(context),
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
        child: child!,
      ),
      home: profileAsync.when(
        loading: () => const Scaffold(body: LoadingView()),
        error: (e, _) => Scaffold(
          body: ErrorView(
            message: "Couldn't load your profile.",
            onRetry: () => ref.invalidate(profileProvider),
          ),
        ),
        data: (profile) =>
            profile.name.isEmpty ? const WelcomeScreen() : const AppShell(),
      ),
    );
  }
}

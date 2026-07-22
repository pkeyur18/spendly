import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'features/settings/theme_mode_provider.dart';

class SpendlyApp extends ConsumerWidget {
  const SpendlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Falls back to system while the persisted value loads.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp(
      title: 'Spendly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}

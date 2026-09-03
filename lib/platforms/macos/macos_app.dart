import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';
import '../../core/theme/app_theme.dart';
import 'macos_database.dart';
import 'macos_shell.dart';

/// Root widget for the read-only macOS build.
///
/// Deliberately separate from [SpendlyApp] (`lib/app.dart`) rather than
/// reusing it behind a flag — that widget wires `home_widget`, local
/// notifications and other mobile-only plugins that have no macOS
/// implementation and would throw if touched here. The macOS build gets its
/// own shell, its own screens, and never calls into mobile-only code.
///
/// [databaseProvider] is overridden with a Mac-only database (its own file
/// under Application Support, see `macos_database.dart`) — every other
/// provider in the app (categories, budgets, accounts, backup, …) is reused
/// completely unmodified and simply reads through to that database.
class MacosSpendlyApp extends StatelessWidget {
  const MacosSpendlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(openMacosDatabase())],
      child: MaterialApp(
        title: 'Spendly',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const MacosShell(),
      ),
    );
  }
}

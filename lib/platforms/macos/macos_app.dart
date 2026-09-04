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
///
/// Uses `overrideWith` (a provider-creation callback Riverpod calls exactly
/// once per container), not `overrideWithValue` — the latter took
/// `openMacosDatabase()` as a plain expression inside `build()`, which
/// constructed a brand new `AppDatabase`/`LazyDatabase` every time this
/// widget rebuilt (any hot reload) and never registered disposal for the
/// old one, producing drift's "AppDatabase created multiple times" warning
/// and a leaked connection. `overrideWith` is the same pattern
/// `databaseProvider`'s own definition already uses in
/// `core/db/providers.dart`.
class MacosSpendlyApp extends StatelessWidget {
  const MacosSpendlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) {
          final db = openMacosDatabase();
          ref.onDispose(db.close);
          return db;
        }),
      ],
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

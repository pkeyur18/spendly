import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/features/settings/theme_mode_provider.dart';

/// ThemeModeNotifier has no coverage yet, despite sharing the exact same
/// AsyncNotifier-over-settings-key shape already tested for
/// AutoBackupSettingsNotifier/ProfileNotifier — same easy-to-apply pattern,
/// just never applied here.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('defaults to system when nothing has been stored', () async {
    final mode = await container.read(themeModeProvider.future);
    expect(mode, ThemeMode.system);
  });

  test('setMode persists and reload returns the same mode', () async {
    await container.read(themeModeProvider.future); // settle initial build
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

    container.invalidate(themeModeProvider);
    final reloaded = await container.read(themeModeProvider.future);
    expect(reloaded, ThemeMode.dark);

    final settings = container.read(settingsRepositoryProvider);
    expect(
      await settings.get(SettingsRepository.themeModeKey),
      ThemeMode.dark.name,
    );
  });

  test('switching modes overwrites the previously stored one', () async {
    await container.read(themeModeProvider.future);
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

    container.invalidate(themeModeProvider);
    final reloaded = await container.read(themeModeProvider.future);
    expect(reloaded, ThemeMode.light);
  });

  test('an unrecognized stored value falls back to system, not a crash',
      () async {
    final settings = container.read(settingsRepositoryProvider);
    await settings.set(SettingsRepository.themeModeKey, 'not_a_real_mode');

    final mode = await container.read(themeModeProvider.future);
    expect(mode, ThemeMode.system);
  });
}

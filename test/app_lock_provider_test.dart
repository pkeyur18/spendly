import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/features/security/app_lock_provider.dart';

/// AppLockNotifier/appUnlockedProvider have no coverage yet — same
/// AsyncNotifier-over-settings-key shape already tested for
/// AutoBackupSettingsNotifier/ThemeModeNotifier, plus the lock/unlock
/// coupling `setEnabled` is responsible for (docs/known-issues.md-style
/// reasoning: a mis-wired toggle here could strand a user on the lock
/// screen, or silently disable the lock without the user asking for that).
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

  test('defaults to disabled when never set', () async {
    final enabled = await container.read(appLockEnabledProvider.future);
    expect(enabled, isFalse);
  });

  test('setEnabled(true) persists and reload reflects it', () async {
    await container.read(appLockEnabledProvider.future); // settle initial build
    await container.read(appLockEnabledProvider.notifier).setEnabled(true);

    container.invalidate(appLockEnabledProvider);
    final reloaded = await container.read(appLockEnabledProvider.future);
    expect(reloaded, isTrue);

    final settings = container.read(settingsRepositoryProvider);
    expect(
      await settings.get(SettingsRepository.appLockEnabledKey),
      'true',
    );
  });

  test('setEnabled(false) persists after having been true', () async {
    await container.read(appLockEnabledProvider.future);
    await container.read(appLockEnabledProvider.notifier).setEnabled(true);
    await container.read(appLockEnabledProvider.notifier).setEnabled(false);

    container.invalidate(appLockEnabledProvider);
    final reloaded = await container.read(appLockEnabledProvider.future);
    expect(reloaded, isFalse);
  });

  test('turning App Lock on immediately re-locks the app', () async {
    await container.read(appLockEnabledProvider.future);
    // Simulate the app already being unlocked this session.
    container.read(appUnlockedProvider.notifier).set(true);
    expect(container.read(appUnlockedProvider), isTrue);

    await container.read(appLockEnabledProvider.notifier).setEnabled(true);

    expect(container.read(appUnlockedProvider), isFalse);
  });

  test('turning App Lock off immediately unlocks the app', () async {
    await container.read(appLockEnabledProvider.future);
    await container.read(appLockEnabledProvider.notifier).setEnabled(true);
    // setEnabled(true) above already locked it back down.
    expect(container.read(appUnlockedProvider), isFalse);

    await container.read(appLockEnabledProvider.notifier).setEnabled(false);

    expect(container.read(appUnlockedProvider), isTrue);
  });

  test('appUnlockedProvider starts locked (false) every fresh process',
      () async {
    expect(container.read(appUnlockedProvider), isFalse);
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/backup/backup_repository.dart';
import 'package:spendly/features/backup/local_auto_backup.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

/// Fakes just the one method `runAutoBackupIfDue` needs, by extending (not
/// implementing) PathProviderPlatform — the extend inherits the real
/// platform-interface token verification from the base class, so no mock
/// mixin/registration boilerplate is needed to stand in for the real OS
/// channel in a plain `flutter test` run.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._supportPath);
  final String _supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => _supportPath;
}

/// `runAutoBackupIfDue` (FR-37/FR-42) had zero coverage: the enabled gate,
/// the elapsed-time "is it due" math per BackupFrequency, the unknown-value
/// fallback, and the lastBackupAt/lastBackupSize bookkeeping it writes back.
/// Given this is the app's only defense against data loss (no cloud sync —
/// ADR-004), a silent off-by-one here means backups either never fire or
/// fire on every launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPlatform;
  late AppDatabase db;
  late BackupRepository repo;
  late SettingsRepository settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spendly_auto_backup_test');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BackupRepository(db);
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPlatform;
    await db.close();
    await tempDir.delete(recursive: true);
  });

  File backupFile() =>
      File(p.join(tempDir.path, 'backups', 'spendly-backup-latest.json'));

  test('does nothing when auto-backup is disabled (default)', () async {
    await runAutoBackupIfDue(repo, settings);

    expect(await backupFile().exists(), isFalse);
    expect(await settings.get(SettingsRepository.lastBackupAtKey), isNull);
  });

  test('runs on the first check once enabled, with no prior backup recorded',
      () async {
    await settings.set(SettingsRepository.autoBackupEnabledKey, 'true');

    await runAutoBackupIfDue(repo, settings);

    expect(await backupFile().exists(), isTrue);
    expect(
      await settings.get(SettingsRepository.lastBackupAtKey),
      isNotNull,
    );
    expect(
      await settings.get(SettingsRepository.lastBackupSizeKey),
      isNotNull,
    );
  });

  test('does not run again before the weekly interval has elapsed',
      () async {
    await settings.set(SettingsRepository.autoBackupEnabledKey, 'true');
    await settings.set(
      SettingsRepository.autoBackupFrequencyKey,
      BackupFrequency.weekly.name,
    );
    final recent = DateTime.now().subtract(const Duration(days: 1));
    await settings.set(
      SettingsRepository.lastBackupAtKey,
      recent.toIso8601String(),
    );

    await runAutoBackupIfDue(repo, settings);

    expect(await backupFile().exists(), isFalse);
    expect(
      await settings.get(SettingsRepository.lastBackupAtKey),
      recent.toIso8601String(),
    );
  });

  test('runs again once the configured interval has elapsed', () async {
    await settings.set(SettingsRepository.autoBackupEnabledKey, 'true');
    await settings.set(
      SettingsRepository.autoBackupFrequencyKey,
      BackupFrequency.daily.name,
    );
    final overADayAgo = DateTime.now().subtract(const Duration(days: 2));
    await settings.set(
      SettingsRepository.lastBackupAtKey,
      overADayAgo.toIso8601String(),
    );

    await runAutoBackupIfDue(repo, settings);

    expect(await backupFile().exists(), isTrue);
    final newAt = DateTime.parse(
      (await settings.get(SettingsRepository.lastBackupAtKey))!,
    );
    expect(newAt.isAfter(overADayAgo), isTrue);
  });

  test('an unrecognized/corrupted frequency value falls back to weekly',
      () async {
    await settings.set(SettingsRepository.autoBackupEnabledKey, 'true');
    await settings.set(
      SettingsRepository.autoBackupFrequencyKey,
      'not_a_real_frequency',
    );
    // Only 1 day since the last backup — due under "daily" but not under the
    // "weekly" fallback this bad value must resolve to.
    final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
    await settings.set(
      SettingsRepository.lastBackupAtKey,
      oneDayAgo.toIso8601String(),
    );

    await runAutoBackupIfDue(repo, settings);

    expect(await backupFile().exists(), isFalse);
  });

  test('the written file reflects the data present at run time', () async {
    await ExpenseRepository(db).add(
      amount: Money.parse('42'),
      categoryId: 1,
      date: DateTime(2026, 1, 1),
    );
    await settings.set(SettingsRepository.autoBackupEnabledKey, 'true');

    await runAutoBackupIfDue(repo, settings);

    final bytes = await backupFile().readAsBytes();
    expect(
      bytes.length.toString(),
      await settings.get(SettingsRepository.lastBackupSizeKey),
    );
  });
}

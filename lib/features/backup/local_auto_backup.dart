import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/providers.dart';
import 'backup_export.dart';
import 'backup_repository.dart';

/// FR-37 cadence options. Default is weekly (matches the prototype's
/// pre-selected chip).
enum BackupFrequency { daily, weekly, monthly }

extension BackupFrequencyX on BackupFrequency {
  /// Simple elapsed-duration math — no calendar-month edge cases needed for
  /// a "has it been about this long" check.
  Duration get interval => switch (this) {
        BackupFrequency.daily => const Duration(days: 1),
        BackupFrequency.weekly => const Duration(days: 7),
        BackupFrequency.monthly => const Duration(days: 30),
      };
}

/// ponytail: there's no background-execution package in this project
/// (workmanager/android_alarm_manager_plus are heavy and flaky cross-platform
/// for a weekly cadence). Auto-backup instead checks elapsed time on app
/// launch/resume (wired in `app.dart`) and runs then — a real OS-scheduled
/// background job is the upgrade path if silent, app-closed backups are ever
/// required. Auto-backups are never password-protected (nobody's present to
/// type one) and never open the share sheet — they only write a local file
/// and update the "last backup" status; delivering it to cloud storage still
/// needs a user tap via "Back up now".
Future<void> runAutoBackupIfDue(BackupRepository repo, SettingsRepository settings) async {
  final enabled = await settings.get(SettingsRepository.autoBackupEnabledKey) == 'true';
  if (!enabled) return;

  final freqName = await settings.get(SettingsRepository.autoBackupFrequencyKey);
  final frequency = BackupFrequency.values
      .firstWhere((f) => f.name == freqName, orElse: () => BackupFrequency.weekly);

  final lastAtRaw = await settings.get(SettingsRepository.lastBackupAtKey);
  final lastAt = lastAtRaw == null ? null : DateTime.tryParse(lastAtRaw);
  final due = lastAt == null || DateTime.now().difference(lastAt) >= frequency.interval;
  if (!due) return;

  final bytes = await buildBackupBytes(repo);
  final backupsDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'backups'));
  await backupsDir.create(recursive: true);
  await File(p.join(backupsDir.path, 'spendly-backup-latest.json')).writeAsBytes(bytes);

  await settings.set(SettingsRepository.lastBackupAtKey, DateTime.now().toIso8601String());
  await settings.set(SettingsRepository.lastBackupSizeKey, bytes.length.toString());
}

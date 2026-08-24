import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';
import 'backup_repository.dart';
import 'local_auto_backup.dart';

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(ref.watch(databaseProvider)),
);

/// FR-42 status display: last successful backup's timestamp + file size.
/// Null fields = no backup has run yet (drives the empty state).
class BackupStatus {
  const BackupStatus({this.lastBackupAt, this.lastBackupSizeBytes});
  final DateTime? lastBackupAt;
  final int? lastBackupSizeBytes;
}

final lastBackupStatusProvider = FutureProvider<BackupStatus>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final atRaw = await settings.get(SettingsRepository.lastBackupAtKey);
  final sizeRaw = await settings.get(SettingsRepository.lastBackupSizeKey);
  return BackupStatus(
    lastBackupAt: atRaw == null ? null : DateTime.tryParse(atRaw),
    lastBackupSizeBytes: sizeRaw == null ? null : int.tryParse(sizeRaw),
  );
});

class AutoBackupSettings {
  const AutoBackupSettings({required this.enabled, required this.frequency});
  final bool enabled;
  final BackupFrequency frequency;
}

/// FR-37 toggle + frequency, persisted in the settings table via the
/// standard settings-backed AsyncNotifier pattern.
class AutoBackupSettingsNotifier extends AsyncNotifier<AutoBackupSettings> {
  @override
  Future<AutoBackupSettings> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    final enabled =
        await settings.get(SettingsRepository.autoBackupEnabledKey) == 'true';
    final freqName = await settings.get(
      SettingsRepository.autoBackupFrequencyKey,
    );
    final frequency = BackupFrequency.values.firstWhere(
      (f) => f.name == freqName,
      orElse: () => BackupFrequency.weekly,
    );
    return AutoBackupSettings(enabled: enabled, frequency: frequency);
  }

  Future<void> setEnabled(bool enabled) async {
    final current =
        state.value ??
        const AutoBackupSettings(
          enabled: false,
          frequency: BackupFrequency.weekly,
        );
    state = AsyncData(
      AutoBackupSettings(enabled: enabled, frequency: current.frequency),
    );
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingsRepository.autoBackupEnabledKey, enabled.toString());
  }

  Future<void> setFrequency(BackupFrequency frequency) async {
    final current =
        state.value ?? AutoBackupSettings(enabled: false, frequency: frequency);
    state = AsyncData(
      AutoBackupSettings(enabled: current.enabled, frequency: frequency),
    );
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingsRepository.autoBackupFrequencyKey, frequency.name);
  }
}

final autoBackupSettingsProvider =
    AsyncNotifierProvider<AutoBackupSettingsNotifier, AutoBackupSettings>(
      AutoBackupSettingsNotifier.new,
    );

/// Runs the app-launch/resume due-check once per invalidation (see
/// `app.dart`'s lifecycle observer, which invalidates this on resume).
final autoBackupCheckProvider = FutureProvider<void>((ref) {
  final repo = ref.watch(backupRepositoryProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  return runAutoBackupIfDue(repo, settings);
});

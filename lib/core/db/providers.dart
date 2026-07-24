import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Single app-wide database. Overridden in tests with an in-memory instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Thin typed accessor over the [Settings] key/value table.
class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  static const themeModeKey = 'theme_mode';

  // Profile (name/email/phone shown on generated reports).
  static const profileNameKey = 'profile_name';
  static const profileEmailKey = 'profile_email';
  static const profilePhoneKey = 'profile_phone';

  // Avatar (FR-51..55). photoPath is device-specific (excluded from backup's
  // generic settings export — see BackupRepository); avatarColorIndex is an
  // ordinary portable setting.
  static const profilePhotoPathKey = 'profile_photo_path';
  static const profileAvatarColorKey = 'profile_avatar_color';

  // Backup bookkeeping (FR-37, FR-42) — excluded from what a backup exports,
  // so restoring one never rewrites the restoring device's own schedule/state.
  static const autoBackupEnabledKey = 'auto_backup_enabled';
  static const autoBackupFrequencyKey = 'auto_backup_frequency';
  static const lastBackupAtKey = 'last_backup_at';
  static const lastBackupSizeKey = 'last_backup_size';

  Future<String?> get(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String? value) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: Value(value)),
        );
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

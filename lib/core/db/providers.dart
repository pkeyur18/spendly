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

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String? value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: Value(value)),
        );
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

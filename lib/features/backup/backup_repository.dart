import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import 'backup_models.dart';

/// Export/import of the full dataset (FR-33, FR-38, FR-39, FR-40). Operates
/// directly on [AppDatabase]'s generated table getters rather than the
/// per-feature repositories — those are scoped to their own CRUD needs, and
/// bolting bulk get-all/wipe-all onto all three just for this one sprint
/// would spread backup logic across files that don't otherwise need it.
class BackupRepository {
  BackupRepository(this._db);
  final AppDatabase _db;

  /// Excluded from the generic settings export/import: backup bookkeeping,
  /// so importing a file elsewhere never overwrites the restoring device's
  /// own schedule/status.
  static const _excludedSettingsKeys = {
    SettingsRepository.autoBackupEnabledKey,
    SettingsRepository.autoBackupFrequencyKey,
    SettingsRepository.lastBackupAtKey,
    SettingsRepository.lastBackupSizeKey,
  };

  /// Everything except the app's own backup bookkeeping (so importing this
  /// file elsewhere never overwrites the restoring device's own schedule).
  Future<BackupPayload> exportAll() async {
    final categories = await _db.select(_db.categories).get();
    final expenses = await _db.select(_db.expenses).get();
    final budgets = await _db.select(_db.budgets).get();
    final settings = await _db.select(_db.settings).get();
    final tags = await _db.select(_db.tags).get();

    return BackupPayload(
      exportedAt: DateTime.now(),
      categories: categories.map(BackupCategory.fromRow).toList(),
      expenses: expenses.map(BackupExpense.fromRow).toList(),
      budgets: budgets.map(BackupBudget.fromRow).toList(),
      settings: settings
          .where((s) => !_excludedSettingsKeys.contains(s.key))
          .map(BackupSetting.fromRow)
          .toList(),
      tags: tags.map(BackupTag.fromRow).toList(),
    );
  }

  /// Wipes all four tables, then restores exactly [payload], reusing its
  /// original ids verbatim (safe — the tables are empty by then). Wrapped in
  /// one transaction: any failure partway through rolls back everything. The
  /// profile photo travels as an ordinary `settings` row (base64 bytes under
  /// [SettingsRepository.profilePhotoBase64Key]), so it round-trips with no
  /// special handling.
  Future<void> replaceAll(BackupPayload payload) async {
    await _db.transaction(() async {
      // Children before parents (FK order).
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.tags).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.settings).go();

      await _db.batch((b) {
        b.insertAll(
          _db.categories,
          payload.categories.map((c) => c.toReplaceCompanion()),
        );
        b.insertAll(_db.tags, payload.tags.map((t) => t.toReplaceCompanion()));
        b.insertAll(
          _db.budgets,
          payload.budgets.map((bg) => bg.toReplaceCompanion()),
        );
        b.insertAll(
          _db.expenses,
          payload.expenses.map((e) => e.toReplaceCompanion()),
        );
        if (payload.settings.isNotEmpty) {
          b.insertAll(
            _db.settings,
            payload.settings.map((s) => s.toCompanion()),
          );
        }
      });
    });
  }

  /// Adds [payload]'s data to what's already on the device without
  /// duplicating it — see the "Merge algorithm" section of
  /// `docs/backup-schema.md` for the natural-key matching rules and their
  /// known ceiling. Settings (profile, theme, and the profile photo — an
  /// ordinary setting like the rest) are never touched by a merge; only
  /// Replace restores them. One transaction.
  Future<void> mergeAll(BackupPayload payload) async {
    await _db.transaction(() async {
      final categoryIdMap = await _mergeCategories(payload.categories);
      final tagIdMap = await _mergeTags(payload.tags);
      await _mergeBudgets(payload.budgets, categoryIdMap);
      await _mergeExpenses(payload.expenses, categoryIdMap, tagIdMap);
    });
  }

  /// Matches by normalized name (every fresh install seeds the same 8
  /// default names, so blind-insert would double them); inserts the rest
  /// individually (not batched) so each new row's assigned id can be
  /// recorded — category counts are small enough that this is fine.
  /// Returns backup-category-id -> local-category-id.
  Future<Map<int, int>> _mergeCategories(
    List<BackupCategory> backupCats,
  ) async {
    final existing = await _db.select(_db.categories).get();
    final byNormalizedName = <String, int>{
      for (final c in existing) _normalize(c.name): c.id,
    };
    var nextSortOrder = existing.isEmpty
        ? 0
        : existing.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    final idMap = <int, int>{};
    for (final c in backupCats) {
      final matchedId = byNormalizedName[_normalize(c.name)];
      if (matchedId != null) {
        idMap[c.id] = matchedId;
        continue;
      }
      final newId = await _db
          .into(_db.categories)
          .insert(c.toInsertCompanion(sortOrder: nextSortOrder));
      idMap[c.id] = newId;
      nextSortOrder++;
    }
    return idMap;
  }

  /// Matches by normalized name, same rule as [_mergeCategories] — tags have
  /// no sort order, so new ones are simply inserted. Returns
  /// backup-tag-id -> local-tag-id.
  Future<Map<int, int>> _mergeTags(List<BackupTag> backupTags) async {
    final existing = await _db.select(_db.tags).get();
    final byNormalizedName = <String, int>{
      for (final t in existing) _normalize(t.name): t.id,
    };

    final idMap = <int, int>{};
    for (final t in backupTags) {
      final matchedId = byNormalizedName[_normalize(t.name)];
      if (matchedId != null) {
        idMap[t.id] = matchedId;
        continue;
      }
      final newId = await _db.into(_db.tags).insert(t.toInsertCompanion());
      idMap[t.id] = newId;
    }
    return idMap;
  }

  /// Matches by (mapped categoryId) slot — null = overall. A slot already
  /// occupied locally is left alone (merge is additive, never overwrites a
  /// budget the user has since changed).
  Future<void> _mergeBudgets(
    List<BackupBudget> backupBudgets,
    Map<int, int> categoryIdMap,
  ) async {
    final existing = await _db.select(_db.budgets).get();
    final occupiedSlots = <int?>{for (final b in existing) b.categoryId};

    final toInsert = <BudgetsCompanion>[];
    for (final b in backupBudgets) {
      int? mappedCategoryId;
      if (b.categoryId != null) {
        mappedCategoryId = categoryIdMap[b.categoryId];
        if (mappedCategoryId == null) continue; // orphan safety net
      }
      if (!occupiedSlots.add(mappedCategoryId)) continue; // slot taken
      toInsert.add(b.toInsertCompanion(mappedCategoryId: mappedCategoryId));
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.budgets, toInsert));
    }
  }

  /// Matches by content fingerprint (amount, date, mapped category, note,
  /// payment method) — the id column isn't stable across devices/reinstalls.
  Future<void> _mergeExpenses(
    List<BackupExpense> backupExpenses,
    Map<int, int> categoryIdMap,
    Map<int, int> tagIdMap,
  ) async {
    final existing = await _db.select(_db.expenses).get();
    final fingerprints = <String>{
      for (final e in existing)
        BackupExpense.fromRow(e).fingerprint(mappedCategoryId: e.categoryId),
    };

    final toInsert = <ExpensesCompanion>[];
    for (final e in backupExpenses) {
      final mappedCategoryId = categoryIdMap[e.categoryId];
      if (mappedCategoryId == null) continue; // orphan safety net
      final fp = e.fingerprint(mappedCategoryId: mappedCategoryId);
      if (!fingerprints.add(fp)) continue; // already present (or dup in file)
      final mappedTagId = e.tagId == null ? null : tagIdMap[e.tagId];
      toInsert.add(
        e.toInsertCompanion(
          mappedCategoryId: mappedCategoryId,
          mappedTagId: mappedTagId,
        ),
      );
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.expenses, toInsert));
    }
  }

  static String _normalize(String name) => name.trim().toLowerCase();
}

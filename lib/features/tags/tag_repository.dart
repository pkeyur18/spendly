import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';

/// Tag CRUD — user-defined grouping across categories (e.g. a vacation trip).
/// Tags are never hard-deleted while referenced by past expenses; they're
/// archived instead, mirroring [CategoryRepository]'s archive-not-delete rule.
class TagRepository {
  TagRepository(this._db);
  final AppDatabase _db;

  Stream<List<TagRow>> watchAll() {
    return (_db.select(
      _db.tags,
    )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).watch();
  }

  /// Active (non-archived) tags shown in the expense entry picker.
  Stream<List<TagRow>> watchActive() {
    return (_db.select(_db.tags)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<int> create({required String name, required int colorValue}) {
    return _db
        .into(_db.tags)
        .insert(TagsCompanion.insert(name: name, colorValue: colorValue));
  }

  Future<void> rename(int id, String name) => _update(id, name: Value(name));
  Future<void> recolor(int id, int colorValue) =>
      _update(id, colorValue: Value(colorValue));
  Future<void> archive(int id) => _update(id, isArchived: const Value(true));
  Future<void> unarchive(int id) => _update(id, isArchived: const Value(false));

  Future<void> _update(
    int id, {
    Value<String> name = const Value.absent(),
    Value<int> colorValue = const Value.absent(),
    Value<bool> isArchived = const Value.absent(),
  }) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(name: name, colorValue: colorValue, isArchived: isArchived),
    );
  }
}

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(databaseProvider)),
);

final activeTagsProvider = StreamProvider<List<TagRow>>(
  (ref) => ref.watch(tagRepositoryProvider).watchActive(),
);

final allTagsProvider = StreamProvider<List<TagRow>>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll(),
);

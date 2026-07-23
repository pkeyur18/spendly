import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';

/// Category CRUD (FR-8,9,10,11). Categories are never hard-deleted while they
/// may be referenced by past expenses — they're archived (FR-11).
class CategoryRepository {
  CategoryRepository(this._db);
  final AppDatabase _db;

  Stream<List<CategoryRow>> watchAll() {
    return (_db.select(
      _db.categories,
    )..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).watch();
  }

  /// Active (non-archived) categories shown in Quick Add / pickers.
  Stream<List<CategoryRow>> watchActive() {
    return (_db.select(_db.categories)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  Future<int> create({
    required String name,
    required String icon,
    required int colorValue,
  }) async {
    final maxOrder = await _maxSortOrder();
    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: name,
            icon: icon,
            colorValue: colorValue,
            sortOrder: Value(maxOrder + 1),
          ),
        );
  }

  Future<void> rename(int id, String name) => _update(id, name: Value(name));
  Future<void> recolor(int id, int colorValue) =>
      _update(id, colorValue: Value(colorValue));
  Future<void> setIcon(int id, String icon) => _update(id, icon: Value(icon));
  Future<void> archive(int id) => _update(id, isArchived: const Value(true));
  Future<void> unarchive(int id) => _update(id, isArchived: const Value(false));

  /// Persist a new ordering. [orderedIds] is the full list top-to-bottom.
  Future<void> reorder(List<int> orderedIds) async {
    await _db.batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          _db.categories,
          CategoriesCompanion(sortOrder: Value(i)),
          where: (t) => t.id.equals(orderedIds[i]),
        );
      }
    });
  }

  Future<void> _update(
    int id, {
    Value<String> name = const Value.absent(),
    Value<String> icon = const Value.absent(),
    Value<int> colorValue = const Value.absent(),
    Value<bool> isArchived = const Value.absent(),
  }) async {
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: name,
        icon: icon,
        colorValue: colorValue,
        isArchived: isArchived,
      ),
    );
  }

  Future<int> _maxSortOrder() async {
    final expr = _db.categories.sortOrder.max();
    final row = await (_db.selectOnly(
      _db.categories,
    )..addColumns([expr])).getSingleOrNull();
    return row?.read(expr) ?? -1;
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);

final activeCategoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchActive(),
);

final allCategoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

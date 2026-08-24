import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';

/// Savings goal CRUD (schema v17). Never hard-deleted from the archived-only
/// convention shared with categories/tags/accounts — a goal you've stopped
/// tracking still has a history worth keeping visible rather than erased.
class GoalRepository {
  GoalRepository(this._db);
  final AppDatabase _db;

  Future<int> create({required String name, required Money target}) => _db
      .into(_db.savingsGoals)
      .insert(
        SavingsGoalsCompanion.insert(name: name, targetMinor: target.minor),
      );

  Future<void> update(int id, {String? name, Money? target}) =>
      (_db.update(_db.savingsGoals)..where((t) => t.id.equals(id))).write(
        SavingsGoalsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          targetMinor: target == null
              ? const Value.absent()
              : Value(target.minor),
        ),
      );

  /// Adds [delta] to the goal's saved total — positive to contribute,
  /// negative to withdraw. Clamped at zero: a withdrawal larger than what's
  /// saved so far never takes the total negative.
  Future<void> adjustSaved(int id, Money delta) async {
    final row = await byId(id);
    if (row == null) return;
    final next = (row.savedMinor + delta.minor).clamp(0, 1 << 62);
    await (_db.update(_db.savingsGoals)..where((t) => t.id.equals(id))).write(
      SavingsGoalsCompanion(savedMinor: Value(next)),
    );
  }

  Future<void> setArchived(int id, bool archived) =>
      (_db.update(_db.savingsGoals)..where((t) => t.id.equals(id))).write(
        SavingsGoalsCompanion(isArchived: Value(archived)),
      );

  Future<void> delete(int id) =>
      (_db.delete(_db.savingsGoals)..where((t) => t.id.equals(id))).go();

  Future<SavingsGoalRow?> byId(int id) => (_db.select(
    _db.savingsGoals,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<SavingsGoalRow>> watchAll() {
    return (_db.select(_db.savingsGoals)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Stream<List<SavingsGoalRow>> watchActive() {
    return (_db.select(_db.savingsGoals)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }
}

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(databaseProvider)),
);

final activeGoalsProvider = StreamProvider<List<SavingsGoalRow>>(
  (ref) => ref.watch(goalRepositoryProvider).watchActive(),
);

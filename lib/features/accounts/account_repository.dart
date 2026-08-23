import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';

/// Account CRUD (schema v12). Never hard-deleted — archived only, matching
/// [CategoryRepository]/[TagRepository]: an account referenced by past
/// expenses must stay resolvable in history and exports.
class AccountRepository {
  AccountRepository(this._db);
  final AppDatabase _db;

  Stream<List<AccountRow>> watchAll() {
    return (_db.select(
      _db.accounts,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  /// Active (non-archived) accounts shown in the Quick Add picker.
  Stream<List<AccountRow>> watchActive() {
    return (_db.select(_db.accounts)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<AccountRow?> byId(int id) =>
      (_db.select(_db.accounts)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> create({
    required String name,
    required AccountType type,
    Money openingBalance = Money.zero,
  }) {
    return _db
        .into(_db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingBalanceMinor: Value(openingBalance.minor),
          ),
        );
  }

  Future<void> update(
    int id, {
    String? name,
    AccountType? type,
    Money? openingBalance,
  }) {
    return (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        type: type == null ? const Value.absent() : Value(type),
        openingBalanceMinor: openingBalance == null
            ? const Value.absent()
            : Value(openingBalance.minor),
      ),
    );
  }

  Future<void> setArchived(int id, bool archived) {
    return (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(isArchived: Value(archived)),
    );
  }

  /// Current spend per account across [start, end) — feeds the per-account
  /// breakdown on the manage screen. Expenses with no account (accountId
  /// null) are excluded, not grouped under a null key, same convention as
  /// [ExpenseRepository.watchTotalsByTag].
  Stream<Map<int, Money>> watchTotalsByAccount(DateTime start, DateTime end) {
    final sum = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.accountId, sum])
      ..where(
        _db.expenses.date.isBiggerOrEqualValue(start) &
            _db.expenses.date.isSmallerThanValue(end) &
            _db.expenses.accountId.isNotNull(),
      )
      ..groupBy([_db.expenses.accountId]);
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.expenses.accountId)!: Money.fromMinor(r.read(sum) ?? 0),
      },
    );
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(databaseProvider)),
);

final allAccountsProvider = StreamProvider<List<AccountRow>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(),
);

final activeAccountsProvider = StreamProvider<List<AccountRow>>(
  (ref) => ref.watch(accountRepositoryProvider).watchActive(),
);

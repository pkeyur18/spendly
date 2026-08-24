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

  Future<AccountRow?> byId(int id) => (_db.select(
    _db.accounts,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The one account Quick Add prefills a fresh expense with, or null if
  /// none is set yet (only possible before the very first account is ever
  /// created — [create] always leaves one designated after that).
  Future<AccountRow?> defaultAccount() => (_db.select(
    _db.accounts,
  )..where((t) => t.isDefault.equals(true))).getSingleOrNull();

  /// The first account ever created becomes the default automatically —
  /// otherwise a single-account user would have to know to go flip a
  /// setting before Quick Add's prefill ever does anything. Every account
  /// after that defaults to not-default; use [setDefault] to reassign it.
  Future<int> create({
    required String name,
    required AccountType type,
    Money openingBalance = Money.zero,
    bool includeInNetWorth = true,
    bool isLiability = false,
    String? customTypeName,
    String? customTypeIcon,
    int? customTypeColorValue,
  }) async {
    final countExpr = _db.accounts.id.count();
    final count = await (_db.selectOnly(
      _db.accounts,
    )..addColumns([countExpr])).map((r) => r.read(countExpr)!).getSingle();
    final isFirst = count == 0;
    return _db
        .into(_db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingBalanceMinor: Value(openingBalance.minor),
            isDefault: Value(isFirst),
            includeInNetWorth: Value(includeInNetWorth),
            isLiability: Value(isLiability),
            customTypeName: Value(customTypeName),
            customTypeIcon: Value(customTypeIcon),
            customTypeColorValue: Value(customTypeColorValue),
          ),
        );
  }

  /// Makes [id] the one default account, clearing it on every other one —
  /// "at most one default" is enforced here, not by a DB constraint (Drift
  /// has no partial-unique-index support in this version).
  Future<void> setDefault(int id) {
    return _db.transaction(() async {
      await (_db.update(_db.accounts)..where((t) => t.isDefault.equals(true)))
          .write(const AccountsCompanion(isDefault: Value(false)));
      await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
        const AccountsCompanion(isDefault: Value(true)),
      );
    });
  }

  /// [updateCustomType] opts into overwriting the three custom-type fields
  /// together, including clearing them to null — unlike every other param
  /// here, `null` on `customTypeName`/`customTypeIcon`/`customTypeColorValue`
  /// is a meaningful value (switching away from [AccountType.custom]), not
  /// "leave unchanged", so a plain nullable param can't express both.
  Future<void> update(
    int id, {
    String? name,
    AccountType? type,
    Money? openingBalance,
    bool? includeInNetWorth,
    bool? isLiability,
    bool updateCustomType = false,
    String? customTypeName,
    String? customTypeIcon,
    int? customTypeColorValue,
  }) {
    return (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        type: type == null ? const Value.absent() : Value(type),
        openingBalanceMinor: openingBalance == null
            ? const Value.absent()
            : Value(openingBalance.minor),
        includeInNetWorth: includeInNetWorth == null
            ? const Value.absent()
            : Value(includeInNetWorth),
        isLiability: isLiability == null
            ? const Value.absent()
            : Value(isLiability),
        customTypeName: updateCustomType
            ? Value(customTypeName)
            : const Value.absent(),
        customTypeIcon: updateCustomType
            ? Value(customTypeIcon)
            : const Value.absent(),
        customTypeColorValue: updateCustomType
            ? Value(customTypeColorValue)
            : const Value.absent(),
      ),
    );
  }

  /// Archiving also clears [AccountRow.isDefault] — an archived account
  /// (hidden from every picker) must never stay "the" default; there is
  /// deliberately no rule for what becomes default in its place, since
  /// picking one automatically could silently redirect future expenses onto
  /// an account the user never chose.
  Future<void> setArchived(int id, bool archived) {
    return (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        isArchived: Value(archived),
        isDefault: archived ? const Value(false) : const Value.absent(),
      ),
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

/// Every account (active and archived — a past expense may reference an
/// archived one) keyed by id, same pattern as `categoriesByIdProvider`.
/// Feeds the Excel/PDF export's Account column.
final accountsByIdProvider = Provider<Map<int, AccountRow>>((ref) {
  final accounts = ref.watch(allAccountsProvider).value ?? const [];
  return {for (final a in accounts) a.id: a};
});

final activeAccountsProvider = StreamProvider<List<AccountRow>>(
  (ref) => ref.watch(accountRepositoryProvider).watchActive(),
);

/// One-shot, not watched: Quick Add reads this once on open (see
/// [_loadReceipt]'s doc comment for why an async fetch, not a synchronous
/// prefill, is the right shape for a field that isn't on [ExpenseRow]) —
/// picking a fresh default mid-edit would silently overwrite what the user
/// already chose.
final defaultAccountProvider = FutureProvider<AccountRow?>(
  (ref) => ref.watch(accountRepositoryProvider).defaultAccount(),
);

/// Spend per account across an arbitrary [(start, end)] range — the manage
/// screen calls it with this month's bounds, the detail screen with an
/// all-time range for the lifetime total. One family provider, not two
/// near-duplicates, since the only thing that differs is the range.
final accountTotalsByRangeProvider =
    StreamProvider.family<Map<int, Money>, (DateTime, DateTime)>(
      (ref, range) => ref
          .watch(accountRepositoryProvider)
          .watchTotalsByAccount(range.$1, range.$2),
    );

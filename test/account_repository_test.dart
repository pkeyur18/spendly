import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/accounts/account_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late ExpenseRepository expenses;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);
    expenses = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  test('create then read back exact fields', () async {
    final id = await accounts.create(
      name: 'HDFC Bank',
      type: AccountType.bank,
      openingBalance: Money.parse('5000'),
    );
    final row = await accounts.byId(id);
    expect(row!.name, 'HDFC Bank');
    expect(row.type, AccountType.bank);
    expect(row.openingBalanceMinor, Money.parse('5000').minor);
    expect(row.isArchived, isFalse);
    expect(row.externalId, isNotNull);
  });

  test('opening balance defaults to zero', () async {
    final id = await accounts.create(name: 'Cash', type: AccountType.cash);
    final row = await accounts.byId(id);
    expect(row!.openingBalanceMinor, 0);
  });

  test('watchAll is alphabetical by name', () async {
    await accounts.create(name: 'Wallet', type: AccountType.wallet);
    await accounts.create(name: 'Bank', type: AccountType.bank);
    await accounts.create(name: 'Cash', type: AccountType.cash);
    final names = (await accounts.watchAll().first).map((a) => a.name);
    expect(names, ['Bank', 'Cash', 'Wallet']);
  });

  test('watchActive excludes archived accounts', () async {
    final keep = await accounts.create(name: 'Keep', type: AccountType.cash);
    final archive = await accounts.create(
      name: 'Archive',
      type: AccountType.cash,
    );
    await accounts.setArchived(archive, true);

    final active = await accounts.watchActive().first;
    expect(active.map((a) => a.id), [keep]);
    // ...but it still exists for history/exports, just not offered to pick.
    expect(await accounts.watchAll().first, hasLength(2));
  });

  test('setArchived(false) un-archives', () async {
    final id = await accounts.create(name: 'Cash', type: AccountType.cash);
    await accounts.setArchived(id, true);
    await accounts.setArchived(id, false);
    expect((await accounts.byId(id))!.isArchived, isFalse);
  });

  test('update changes only the given fields', () async {
    final id = await accounts.create(
      name: 'Old name',
      type: AccountType.cash,
      openingBalance: Money.parse('100'),
    );
    await accounts.update(id, name: 'New name');
    final row = await accounts.byId(id);
    expect(row!.name, 'New name');
    expect(row.type, AccountType.cash); // untouched
    expect(row.openingBalanceMinor, Money.parse('100').minor); // untouched
  });

  group('watchTotalsByAccount', () {
    test('groups spend by account within the range', () async {
      final bank = await accounts.create(name: 'Bank', type: AccountType.bank);
      final cash = await accounts.create(name: 'Cash', type: AccountType.cash);
      await expenses.add(
        amount: Money.parse('100'),
        categoryId: 1,
        date: DateTime(2026, 6, 5),
        accountId: bank,
      );
      await expenses.add(
        amount: Money.parse('50'),
        categoryId: 1,
        date: DateTime(2026, 6, 10),
        accountId: bank,
      );
      await expenses.add(
        amount: Money.parse('30'),
        categoryId: 1,
        date: DateTime(2026, 6, 15),
        accountId: cash,
      );

      final totals = await accounts
          .watchTotalsByAccount(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
          .first;
      expect(totals[bank], Money.parse('150'));
      expect(totals[cash], Money.parse('30'));
    });

    test('excludes expenses with no account, does not group them under null',
        () async {
      await expenses.add(
        amount: Money.parse('999'),
        categoryId: 1,
        date: DateTime(2026, 6, 5),
      );
      final totals = await accounts
          .watchTotalsByAccount(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
          .first;
      expect(totals, isEmpty);
      expect(totals.containsKey(null), isFalse);
    });

    test('stays inside the date range', () async {
      final bank = await accounts.create(name: 'Bank', type: AccountType.bank);
      await expenses.add(
        amount: Money.parse('100'),
        categoryId: 1,
        date: DateTime(2026, 5, 20),
        accountId: bank,
      );
      final totals = await accounts
          .watchTotalsByAccount(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
          .first;
      expect(totals[bank], isNull);
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
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

  group('default account', () {
    test('no default before any account exists', () async {
      expect(await accounts.defaultAccount(), isNull);
    });

    test('the first account ever created becomes default automatically',
        () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      final row = await accounts.byId(id);
      expect(row!.isDefault, isTrue);
      expect((await accounts.defaultAccount())!.id, id);
    });

    test('a second account does not become default on its own', () async {
      await accounts.create(name: 'Cash', type: AccountType.cash);
      final second = await accounts.create(
        name: 'Bank',
        type: AccountType.bank,
      );
      expect((await accounts.byId(second))!.isDefault, isFalse);
    });

    test('setDefault reassigns it, clearing the previous one', () async {
      final first = await accounts.create(name: 'Cash', type: AccountType.cash);
      final second = await accounts.create(
        name: 'Bank',
        type: AccountType.bank,
      );

      await accounts.setDefault(second);

      expect((await accounts.byId(first))!.isDefault, isFalse);
      expect((await accounts.byId(second))!.isDefault, isTrue);
      expect((await accounts.defaultAccount())!.id, second);
    });

    test('archiving the default account clears the flag, no replacement '
        'chosen automatically', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.setArchived(id, true);

      expect((await accounts.byId(id))!.isDefault, isFalse);
      expect(await accounts.defaultAccount(), isNull);
    });

    test('unarchiving does not restore default status on its own', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.setArchived(id, true);
      await accounts.setArchived(id, false);
      expect((await accounts.byId(id))!.isDefault, isFalse);
    });

    test('archiving a non-default account leaves the real default alone',
        () async {
      final first = await accounts.create(name: 'Cash', type: AccountType.cash);
      final second = await accounts.create(
        name: 'Bank',
        type: AccountType.bank,
      );
      await accounts.setArchived(second, true);
      expect((await accounts.byId(first))!.isDefault, isTrue);
    });
  });

  group('opening balance', () {
    test('create persists it', () async {
      final id = await accounts.create(
        name: 'Cash',
        type: AccountType.cash,
        openingBalance: Money.parse('500'),
      );
      final row = (await accounts.byId(id))!;
      expect(row.openingBalance, Money.parse('500'));
    });

    test('update changes it', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.update(id, openingBalance: Money.parse('200'));
      final row = (await accounts.byId(id))!;
      expect(row.openingBalance, Money.parse('200'));
    });

    test('never resets on its own — reads back unchanged regardless of when '
        'it was set', () async {
      final id = await accounts.create(
        name: 'Cash',
        type: AccountType.cash,
        openingBalance: Money.parse('500'),
      );
      // No further writes at all — simulates months passing with the
      // account untouched. The old monthly-reset mechanic used to zero this
      // out once the calendar moved on; it no longer exists.
      final row = (await accounts.byId(id))!;
      expect(row.openingBalance, Money.parse('500'));
    });

    test('a fresh account with no opening balance reads zero', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      final row = (await accounts.byId(id))!;
      expect(row.openingBalance, Money.zero);
    });
  });

  group('includeInNetWorth', () {
    test('create defaults to true', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      expect((await accounts.byId(id))!.includeInNetWorth, isTrue);
    });

    test('create can opt out', () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.bank,
        includeInNetWorth: false,
      );
      expect((await accounts.byId(id))!.includeInNetWorth, isFalse);
    });

    test('update flips it either way', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.update(id, includeInNetWorth: false);
      expect((await accounts.byId(id))!.includeInNetWorth, isFalse);
      await accounts.update(id, includeInNetWorth: true);
      expect((await accounts.byId(id))!.includeInNetWorth, isTrue);
    });

    test('updating other fields leaves it alone', () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.bank,
        includeInNetWorth: false,
      );
      await accounts.update(id, name: 'Car loan (Axis)');
      expect((await accounts.byId(id))!.includeInNetWorth, isFalse);
    });
  });

  group('isLiability', () {
    test('create defaults to false', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      expect((await accounts.byId(id))!.isLiability, isFalse);
    });

    test('create can mark a liability, storing a negative opening balance',
        () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.bank,
        openingBalance: Money.parse('-1000000'),
        isLiability: true,
      );
      final row = (await accounts.byId(id))!;
      expect(row.isLiability, isTrue);
      expect(row.openingBalance, Money.parse('-1000000'));
    });

    test('update flips it either way', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.update(id, isLiability: true);
      expect((await accounts.byId(id))!.isLiability, isTrue);
      await accounts.update(id, isLiability: false);
      expect((await accounts.byId(id))!.isLiability, isFalse);
    });

    test('updating other fields leaves it alone', () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.bank,
        isLiability: true,
      );
      await accounts.update(id, name: 'Car loan (Axis)');
      expect((await accounts.byId(id))!.isLiability, isTrue);
    });
  });

  group('isFrequent', () {
    test('create defaults to false', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      expect((await accounts.byId(id))!.isFrequent, isFalse);
    });

    test('setFrequent flips it either way', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.setFrequent(id, true);
      expect((await accounts.byId(id))!.isFrequent, isTrue);
      await accounts.setFrequent(id, false);
      expect((await accounts.byId(id))!.isFrequent, isFalse);
    });

    test('any number of accounts can be frequent at once', () async {
      final first = await accounts.create(name: 'Cash', type: AccountType.cash);
      final second = await accounts.create(
        name: 'Bank',
        type: AccountType.bank,
      );
      await accounts.setFrequent(first, true);
      await accounts.setFrequent(second, true);
      expect((await accounts.byId(first))!.isFrequent, isTrue);
      expect((await accounts.byId(second))!.isFrequent, isTrue);
    });

    test('is independent of isDefault', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      // create() makes the first account default automatically.
      expect((await accounts.byId(id))!.isDefault, isTrue);
      expect((await accounts.byId(id))!.isFrequent, isFalse);
      await accounts.setFrequent(id, true);
      expect((await accounts.byId(id))!.isDefault, isTrue);
      expect((await accounts.byId(id))!.isFrequent, isTrue);
    });

    test('archiving a frequent account clears the flag', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.setFrequent(id, true);
      await accounts.setArchived(id, true);
      expect((await accounts.byId(id))!.isFrequent, isFalse);
    });

    test('unarchiving does not restore the frequent flag on its own',
        () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      await accounts.setFrequent(id, true);
      await accounts.setArchived(id, true);
      await accounts.setArchived(id, false);
      expect((await accounts.byId(id))!.isFrequent, isFalse);
    });

    test('archiving a non-frequent account leaves other accounts\' flags '
        'alone', () async {
      final frequent = await accounts.create(
        name: 'Cash',
        type: AccountType.cash,
      );
      final other = await accounts.create(name: 'Bank', type: AccountType.bank);
      await accounts.setFrequent(frequent, true);
      await accounts.setArchived(other, true);
      expect((await accounts.byId(frequent))!.isFrequent, isTrue);
    });
  });

  group('custom account type', () {
    test('create persists name, icon and color', () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.custom,
        customTypeName: 'Loan',
        customTypeIcon: '🏦',
        customTypeColorValue: 0xFF00FF00,
      );
      final row = (await accounts.byId(id))!;
      expect(row.type, AccountType.custom);
      expect(row.customTypeName, 'Loan');
      expect(row.customTypeIcon, '🏦');
      expect(row.customTypeColorValue, 0xFF00FF00);
    });

    test('a built-in type has no custom fields set', () async {
      final id = await accounts.create(name: 'Cash', type: AccountType.cash);
      final row = (await accounts.byId(id))!;
      expect(row.customTypeName, isNull);
      expect(row.customTypeIcon, isNull);
      expect(row.customTypeColorValue, isNull);
    });

    test('update with updateCustomType changes all three together', () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.custom,
        customTypeName: 'Loan',
        customTypeIcon: '🏦',
        customTypeColorValue: 0xFF00FF00,
      );
      await accounts.update(
        id,
        updateCustomType: true,
        customTypeName: 'Auto loan',
        customTypeIcon: '🚗',
        customTypeColorValue: 0xFFFF0000,
      );
      final row = (await accounts.byId(id))!;
      expect(row.customTypeName, 'Auto loan');
      expect(row.customTypeIcon, '🚗');
      expect(row.customTypeColorValue, 0xFFFF0000);
    });

    test('update without updateCustomType leaves the custom fields alone',
        () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.custom,
        customTypeName: 'Loan',
        customTypeIcon: '🏦',
        customTypeColorValue: 0xFF00FF00,
      );
      await accounts.update(id, name: 'Car loan (Axis)');
      final row = (await accounts.byId(id))!;
      expect(row.name, 'Car loan (Axis)');
      expect(row.customTypeName, 'Loan');
    });

    test('switching type away from custom clears the fields when '
        'updateCustomType is passed', () async {
      final id = await accounts.create(
        name: 'Car loan',
        type: AccountType.custom,
        customTypeName: 'Loan',
        customTypeIcon: '🏦',
        customTypeColorValue: 0xFF00FF00,
      );
      await accounts.update(
        id,
        type: AccountType.bank,
        updateCustomType: true,
        // customTypeName/Icon/ColorValue omitted -> null, clearing them.
      );
      final row = (await accounts.byId(id))!;
      expect(row.type, AccountType.bank);
      expect(row.customTypeName, isNull);
      expect(row.customTypeIcon, isNull);
      expect(row.customTypeColorValue, isNull);
    });
  });
}

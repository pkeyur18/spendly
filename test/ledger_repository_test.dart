import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/accounts/account_repository.dart';
import 'package:spendly/features/ledger/ledger_repository.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late AccountRepository accounts;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    accounts = AccountRepository(db);
  });
  tearDown(() => db.close());

  test('addIncome then read back exact fields', () async {
    final id = await ledger.addIncome(
      amount: Money.parse('50000'),
      date: DateTime(2026, 6, 1),
      sourceLabel: 'Salary',
      note: 'June',
    );
    final row = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.amountMinor, Money.parse('50000').minor);
    expect(row.date, DateTime(2026, 6, 1));
    expect(row.sourceLabel, 'Salary');
    expect(row.note, 'June');
    expect(row.accountId, isNull);
    expect(row.externalId, isNotNull);
  });

  test('addIncome with an account attaches it', () async {
    final accountId = await accounts.create(
      name: 'HDFC Bank',
      type: AccountType.bank,
    );
    final id = await ledger.addIncome(
      amount: Money.parse('1000'),
      date: DateTime(2026, 6, 1),
      accountId: accountId,
    );
    final row = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.accountId, accountId);
  });

  test('update changes only the given fields', () async {
    final id = await ledger.addIncome(
      amount: Money.parse('1000'),
      date: DateTime(2026, 6, 1),
      sourceLabel: 'Freelance',
    );
    await ledger.update(id, amount: Money.parse('1500'));
    final row = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.amountMinor, Money.parse('1500').minor);
    expect(row.sourceLabel, 'Freelance'); // untouched
    expect(row.date, DateTime(2026, 6, 1)); // untouched
  });

  test('update clearAccount removes the account without touching other fields',
      () async {
    final accountId = await accounts.create(name: 'Cash', type: AccountType.cash);
    final id = await ledger.addIncome(
      amount: Money.parse('1000'),
      date: DateTime(2026, 6, 1),
      accountId: accountId,
    );
    await ledger.update(id, clearAccount: true);
    final row = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.accountId, isNull);
    expect(row.amountMinor, Money.parse('1000').minor); // untouched
  });

  test('delete then restore puts the row back with the same id and externalId',
      () async {
    final id = await ledger.addIncome(
      amount: Money.parse('1000'),
      date: DateTime(2026, 6, 1),
      sourceLabel: 'Salary',
    );
    final original = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(id))).getSingle();

    await ledger.delete(id);
    expect(await ledger.watchAll().first, isEmpty);

    await ledger.restore(original);
    final restored = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(restored.id, original.id);
    expect(restored.externalId, original.externalId);
    expect(restored.sourceLabel, 'Salary');
  });

  test('watchInRange stays inside the range, newest first', () async {
    await ledger.addIncome(amount: Money.parse('100'), date: DateTime(2026, 5, 20));
    final juneId = await ledger.addIncome(
      amount: Money.parse('200'),
      date: DateTime(2026, 6, 5),
    );
    final laterJuneId = await ledger.addIncome(
      amount: Money.parse('300'),
      date: DateTime(2026, 6, 20),
    );

    final rows = await ledger
        .watchInRange(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
        .first;
    expect(rows.map((r) => r.id), [laterJuneId, juneId]);
  });

  test('watchTotalInRange sums only entries inside the range', () async {
    await ledger.addIncome(amount: Money.parse('100'), date: DateTime(2026, 5, 20));
    await ledger.addIncome(amount: Money.parse('200'), date: DateTime(2026, 6, 5));
    await ledger.addIncome(amount: Money.parse('300'), date: DateTime(2026, 6, 20));

    final total = await ledger
        .watchTotalInRange(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
        .first;
    expect(total, Money.parse('500'));
  });

  test('watchTotalInRange is zero, not an error, when nothing is in range',
      () async {
    final total = await ledger
        .watchTotalInRange(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
        .first;
    expect(total, Money.zero);
  });

  test('watchTotalInRange excludes transfers — moving money isn\'t income',
      () async {
    final a = await accounts.create(name: 'Cash', type: AccountType.cash);
    final b = await accounts.create(name: 'Bank', type: AccountType.bank);
    await ledger.addIncome(amount: Money.parse('500'), date: DateTime(2026, 6, 5));
    await ledger.addTransfer(
      amount: Money.parse('300'),
      date: DateTime(2026, 6, 6),
      fromAccountId: a,
      toAccountId: b,
    );
    final total = await ledger
        .watchTotalInRange(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
        .first;
    expect(total, Money.parse('500'));
  });

  test('watchAll (Income screen) excludes transfers', () async {
    final a = await accounts.create(name: 'Cash', type: AccountType.cash);
    final b = await accounts.create(name: 'Bank', type: AccountType.bank);
    await ledger.addIncome(amount: Money.parse('500'), date: DateTime(2026, 6, 5));
    await ledger.addTransfer(
      amount: Money.parse('300'),
      date: DateTime(2026, 6, 6),
      fromAccountId: a,
      toAccountId: b,
    );
    final rows = await ledger.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.kind, LedgerEntryKind.income);
  });

  group('transfers', () {
    test('addTransfer then read back exact fields', () async {
      final a = await accounts.create(name: 'Cash', type: AccountType.cash);
      final b = await accounts.create(name: 'Bank', type: AccountType.bank);
      final id = await ledger.addTransfer(
        amount: Money.parse('750'),
        date: DateTime(2026, 6, 10),
        fromAccountId: a,
        toAccountId: b,
        note: 'Moved savings',
      );
      final row = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.kind, LedgerEntryKind.transfer);
      expect(row.accountId, a);
      expect(row.counterAccountId, b);
      expect(row.amountMinor, Money.parse('750').minor);
      expect(row.note, 'Moved savings');
    });

    test('update can re-point both accounts on a transfer', () async {
      final a = await accounts.create(name: 'Cash', type: AccountType.cash);
      final b = await accounts.create(name: 'Bank', type: AccountType.bank);
      final c = await accounts.create(name: 'Wallet', type: AccountType.wallet);
      final id = await ledger.addTransfer(
        amount: Money.parse('100'),
        date: DateTime(2026, 6, 10),
        fromAccountId: a,
        toAccountId: b,
      );
      await ledger.update(id, accountId: c, counterAccountId: a);
      final row = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.accountId, c);
      expect(row.counterAccountId, a);
    });

    test('watchIncomeTotalsByAccount is grouped and excludes transfers',
        () async {
      final a = await accounts.create(name: 'Cash', type: AccountType.cash);
      final b = await accounts.create(name: 'Bank', type: AccountType.bank);
      await ledger.addIncome(
        amount: Money.parse('500'),
        date: DateTime(2026, 6, 5),
        accountId: a,
      );
      await ledger.addIncome(
        amount: Money.parse('200'),
        date: DateTime(2026, 6, 6),
        accountId: a,
      );
      await ledger.addIncome(
        amount: Money.parse('100'),
        date: DateTime(2026, 6, 7),
        accountId: b,
      );
      await ledger.addTransfer(
        amount: Money.parse('999'),
        date: DateTime(2026, 6, 8),
        fromAccountId: a,
        toAccountId: b,
      );
      final totals = await ledger
          .watchIncomeTotalsByAccount(DateTime(2026, 6, 1), DateTime(2026, 7, 1))
          .first;
      expect(totals[a], Money.parse('700'));
      expect(totals[b], Money.parse('100'));
    });

    test('watchTransfersOutTotalsByAccount / watchTransfersInTotalsByAccount '
        'attribute the right side to the right account', () async {
      final a = await accounts.create(name: 'Cash', type: AccountType.cash);
      final b = await accounts.create(name: 'Bank', type: AccountType.bank);
      await ledger.addTransfer(
        amount: Money.parse('300'),
        date: DateTime(2026, 6, 6),
        fromAccountId: a,
        toAccountId: b,
      );
      await ledger.addTransfer(
        amount: Money.parse('50'),
        date: DateTime(2026, 6, 7),
        fromAccountId: a,
        toAccountId: b,
      );
      final range = (DateTime(2026, 6, 1), DateTime(2026, 7, 1));
      final out = await ledger
          .watchTransfersOutTotalsByAccount(range.$1, range.$2)
          .first;
      final into = await ledger
          .watchTransfersInTotalsByAccount(range.$1, range.$2)
          .first;
      expect(out[a], Money.parse('350'));
      expect(out.containsKey(b), isFalse);
      expect(into[b], Money.parse('350'));
      expect(into.containsKey(a), isFalse);
    });

    test('watchTouchingAccount unions income landed in it and transfers on '
        'either side of it', () async {
      final a = await accounts.create(name: 'Cash', type: AccountType.cash);
      final b = await accounts.create(name: 'Bank', type: AccountType.bank);
      final c = await accounts.create(name: 'Wallet', type: AccountType.wallet);
      final incomeId = await ledger.addIncome(
        amount: Money.parse('500'),
        date: DateTime(2026, 6, 1),
        accountId: a,
      );
      final transferOutId = await ledger.addTransfer(
        amount: Money.parse('100'),
        date: DateTime(2026, 6, 2),
        fromAccountId: a,
        toAccountId: b,
      );
      final transferInId = await ledger.addTransfer(
        amount: Money.parse('50'),
        date: DateTime(2026, 6, 3),
        fromAccountId: c,
        toAccountId: a,
      );
      // Doesn't touch account a at all — must not appear.
      await ledger.addTransfer(
        amount: Money.parse('999'),
        date: DateTime(2026, 6, 4),
        fromAccountId: b,
        toAccountId: c,
      );

      final rows = await ledger
          .watchTouchingAccount(a, DateTime(2026, 6, 1), DateTime(2026, 7, 1))
          .first;
      expect(
        rows.map((r) => r.id).toSet(),
        {incomeId, transferOutId, transferInId},
      );
    });
  });
}

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
}

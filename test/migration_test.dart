import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/money.dart';

/// Raw CREATE TABLE statements reconstructing the schema exactly as it was
/// at v1 (commit aaf6d2f), before any `onUpgrade` block ever ran. Verified
/// against `git show aaf6d2f:lib/core/db/database.dart` — this is the real
/// original schema, not a guess.
const _v1Schema = [
  '''
  CREATE TABLE categories (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    icon TEXT NOT NULL,
    color_value INTEGER NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_archived INTEGER NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE budgets (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER REFERENCES categories(id),
    amount_minor INTEGER NOT NULL,
    period TEXT NOT NULL DEFAULT 'monthly'
  )
  ''',
  '''
  CREATE TABLE settings (
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY (key)
  )
  ''',
  '''
  CREATE TABLE expenses (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    amount_minor INTEGER NOT NULL,
    category_id INTEGER NOT NULL REFERENCES categories(id),
    date INTEGER NOT NULL,
    note TEXT,
    payment_method TEXT,
    is_recurring INTEGER NOT NULL DEFAULT 0,
    recurrence TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
];

void main() {
  test('v1 -> v17 upgrade produces a working schema with backfilled data', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (rawDb) {
          for (final statement in _v1Schema) {
            rawDb.execute(statement);
          }
          rawDb.execute('''
            INSERT INTO categories (name, icon, color_value)
            VALUES ('Rent', '🏠', 6636321)
          ''');
          rawDb.execute('''
            INSERT INTO budgets (category_id, amount_minor)
            VALUES (1, 10000)
          ''');
          // A pre-existing expense, so from<8's ADD COLUMN runs against a
          // POPULATED table — the exact case that breaks on a NOT NULL column
          // with no default.
          rawDb.execute('''
            INSERT INTO expenses
              (amount_minor, category_id, date, created_at, updated_at)
            VALUES (24500, 1, 1750000000, 1750000000, 1750000000)
          ''');
          // A row already flagged recurring before any scheduling existed —
          // from<10 must add its columns without inventing a due date for it.
          rawDb.execute('''
            INSERT INTO expenses
              (amount_minor, category_id, date, is_recurring, recurrence,
               created_at, updated_at)
            VALUES (2000000, 1, 1750000000, 1, 'monthly', 1750000000,
                    1750000000)
          ''');
          // Two pre-existing rows sharing a payment_method value, plus one
          // with none — from<12 must turn 'UPI' into exactly one Accounts
          // row, point both matching expenses at it, and leave the null one
          // untouched.
          rawDb.execute('''
            INSERT INTO expenses
              (amount_minor, category_id, date, payment_method,
               created_at, updated_at)
            VALUES (5000, 1, 1750000000, 'UPI', 1750000000, 1750000000)
          ''');
          rawDb.execute('''
            INSERT INTO expenses
              (amount_minor, category_id, date, payment_method,
               created_at, updated_at)
            VALUES (7500, 1, 1750000000, 'UPI', 1750000000, 1750000000)
          ''');
          rawDb.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    // Migration runs lazily on first use — this drives it through every
    // `if (from < N)` block (2 through 12) in one pass, since the seeded
    // database starts at v1.
    final categories = await db.select(db.categories).get();
    final budgets = await db.select(db.budgets).get();
    final expenses = await db.select(db.expenses).get();
    final tags = await db.select(db.tags).get();

    // from<3 seeds 10 more default categories onto every existing install —
    // the pre-existing "Rent" row plus those 10.
    expect(categories, hasLength(11));
    expect(budgets, hasLength(1));
    expect(expenses, hasLength(4));
    expect(tags, isEmpty);

    final category = categories.firstWhere((c) => c.name == 'Rent');
    final budget = budgets.single;

    // from<6: isIgnoredForBudget backfills to its declared default.
    expect(category.isIgnoredForBudget, isFalse);

    // from<2: monthKey backfills to the current month for pre-existing rows.
    expect(budget.monthKey, monthKeyFor(DateTime.now()));

    // from<7: externalId backfills for every pre-existing row.
    expect(category.externalId, isNotNull);
    expect(category.externalId, isNotEmpty);
    expect(budget.externalId, isNotNull);
    expect(budget.externalId, isNotEmpty);

    // from<8: the fx columns land on the populated expenses table and read
    // back null — a pre-v8 expense was, and stays, home currency.
    final expense = expenses.firstWhere((e) => e.amountMinor == 24500);
    expect(expense.fxCurrency, isNull);
    expect(expense.fxAmountMinor, isNull);
    expect(expense.isForeign, isFalse);

    // from<8 and from<9 on `tags`: the table was created at from<4 from the
    // CURRENT definition, so it already had the fx AND trip-date columns and
    // both guards must have skipped re-adding them. Reaching this line at all
    // proves no duplicate-column error was thrown; assert they're queryable.
    final tagFx = await db
        .customSelect(
          'SELECT fx_currency, fx_rate_micros, trip_start_date, '
          'trip_end_date FROM tags',
        )
        .get();
    expect(tagFx, isEmpty);

    // from<9 on `expenses`/a fresh tag insert: trip dates read back null on
    // a tag that never set them.
    final tagId = await db
        .into(db.tags)
        .insert(TagsCompanion.insert(name: 'Weekend', colorValue: 0xFF6366F1));
    final tag = await (db.select(
      db.tags,
    )..where((t) => t.id.equals(tagId))).getSingle();
    expect(tag.tripStartDate, isNull);
    expect(tag.tripEndDate, isNull);

    // from<10: the scheduling columns land on the populated expenses table.
    // The pre-existing recurring row keeps its flag but gets NO invented due
    // date — there is nothing to reconstruct one from, and a guessed date
    // would fire a reminder the user never asked for.
    final recurring = expenses.firstWhere((e) => e.isRecurring);
    expect(recurring.recurrence, Recurrence.monthly);
    expect(recurring.nextDueDate, isNull);
    expect(recurring.recurrenceEndDate, isNull);
    // The non-recurring row is untouched by all of this.
    expect(expense.isRecurring, isFalse);
    expect(expense.nextDueDate, isNull);

    // from<11: expense_receipts is a whole new table (no populated-table
    // hazard to guard against), and a receipt attaches cleanly to a
    // pre-existing, migrated expense row.
    await db
        .into(db.expenseReceipts)
        .insert(
          ExpenseReceiptsCompanion.insert(
            expenseId: expense.id,
            photoBytes: Uint8List.fromList([1, 2, 3]),
          ),
        );
    final receipt = await (db.select(
      db.expenseReceipts,
    )..where((t) => t.expenseId.equals(expense.id))).getSingle();
    expect(receipt.photoBytes, [1, 2, 3]);

    // from<12: exactly one 'UPI' account, both matching expenses pointed at
    // it, and payment_method itself left untouched (still readable, not
    // cleared) — account_id is additive, not a replacement.
    final accounts = await db.select(db.accounts).get();
    expect(accounts, hasLength(1));
    final upi = accounts.single;
    expect(upi.name, 'UPI');
    expect(upi.type, AccountType.cash);
    expect(upi.openingBalanceMinor, 0);

    final upiExpenses =
        expenses.where((e) => e.paymentMethod == 'UPI').toList();
    expect(upiExpenses, hasLength(2));
    // `expenses` was captured before the migration ran further writes in
    // this same test, so re-read fresh rather than trust the stale list.
    final reloaded = await db.select(db.expenses).get();
    for (final e in reloaded.where((e) => e.paymentMethod == 'UPI')) {
      expect(e.accountId, upi.id);
    }
    // The pre-existing rows with no payment_method are untouched.
    expect(
      reloaded.where((e) => e.paymentMethod == null).every(
        (e) => e.accountId == null,
      ),
      isTrue,
    );

    // from<13: an install upgrading with an account already on the books
    // (from the v12 payment-method migration, in this same pass) gets it
    // auto-marked default — otherwise Quick Add's prefill would stay silent
    // for every upgrading user, not just new installs.
    final reloadedAccounts = await db.select(db.accounts).get();
    expect(reloadedAccounts.single.isDefault, isTrue);

    // from<14: the migrated account never had an opening balance entered.
    expect(reloadedAccounts.single.openingBalanceMonth, isNull);
    expect(reloadedAccounts.single.openingBalance, Money.zero);

    // from<15: ledger_entries is a whole new table (no populated-table
    // hazard), queryable right away.
    final entryId = await db
        .into(db.ledgerEntries)
        .insert(
          LedgerEntriesCompanion.insert(
            amountMinor: 50000,
            date: DateTime(2026, 6, 1),
          ),
        );
    final entry = await (db.select(
      db.ledgerEntries,
    )..where((t) => t.id.equals(entryId))).getSingle();
    expect(entry.amountMinor, 50000);
    expect(entry.externalId, isNotNull);

    // from<16: this same v1-start upgrade already created ledger_entries at
    // from<15 (via m.createTable, which always emits the CURRENT — v16 —
    // definition), so kind/counter_account_id exist from that single
    // createTable call. A fresh insert with no kind specified defaults to
    // income, same as every row that existed before transfers did.
    expect(entry.kind, LedgerEntryKind.income);
    expect(entry.counterAccountId, isNull);

    // from<17: savings_goals is a whole new table (no populated-table
    // hazard), queryable right away.
    final goalId = await db
        .into(db.savingsGoals)
        .insert(
          SavingsGoalsCompanion.insert(name: 'New laptop', targetMinor: 80000),
        );
    final goal = await (db.select(
      db.savingsGoals,
    )..where((t) => t.id.equals(goalId))).getSingle();
    expect(goal.name, 'New laptop');
    expect(goal.savedMinor, 0);
    expect(goal.externalId, isNotNull);

    // from<18: the account created above (from<13's own payment-method
    // migration path) already has include_in_net_worth from that single
    // createTable call — same "createTable trap" as openingBalanceMonth.
    // Defaults true, same as any pre-v18 account would read once upgraded.
    expect(reloadedAccounts.single.includeInNetWorth, isTrue);

    // from<19: same createTable trap again — is_liability defaults false,
    // same as any pre-v19 account (an asset) would read once upgraded.
    expect(reloadedAccounts.single.isLiability, isFalse);

    // from<20: same createTable trap once more — the custom-type columns
    // default to null, same as any pre-v20 account (none of which were
    // custom) would read once upgraded.
    expect(reloadedAccounts.single.customTypeName, isNull);
    expect(reloadedAccounts.single.customTypeIcon, isNull);
    expect(reloadedAccounts.single.customTypeColorValue, isNull);
  });
}

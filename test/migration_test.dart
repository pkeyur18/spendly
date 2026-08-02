import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';

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
  test('v1 -> v9 upgrade produces a working schema with backfilled data', () async {
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
          rawDb.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    // Migration runs lazily on first use — this drives it through every
    // `if (from < N)` block (2 through 9) in one pass, since the seeded
    // database starts at v1.
    final categories = await db.select(db.categories).get();
    final budgets = await db.select(db.budgets).get();
    final expenses = await db.select(db.expenses).get();
    final tags = await db.select(db.tags).get();

    // from<3 seeds 10 more default categories onto every existing install —
    // the pre-existing "Rent" row plus those 10.
    expect(categories, hasLength(11));
    expect(budgets, hasLength(1));
    expect(expenses, hasLength(1));
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
    final expense = expenses.single;
    expect(expense.amountMinor, 24500);
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
  });
}

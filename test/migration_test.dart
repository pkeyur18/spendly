import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';

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
  test('v1 -> v7 upgrade produces a working schema with backfilled data', () async {
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
          rawDb.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    // Migration runs lazily on first use — this drives it through every
    // `if (from < N)` block (2 through 7) in one pass, since the seeded
    // database starts at v1.
    final categories = await db.select(db.categories).get();
    final budgets = await db.select(db.budgets).get();
    final expenses = await db.select(db.expenses).get();
    final tags = await db.select(db.tags).get();

    // from<3 seeds 10 more default categories onto every existing install —
    // the pre-existing "Rent" row plus those 10.
    expect(categories, hasLength(11));
    expect(budgets, hasLength(1));
    expect(expenses, isEmpty);
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
  });
}

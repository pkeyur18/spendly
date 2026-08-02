import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'external_id.dart';

part 'database.g.dart';

/// How often a recurring expense repeats (FR-7). v1 behavior = remind + confirm,
/// so this drives the reminder schedule, not silent auto-logging.
enum Recurrence { daily, weekly, monthly }

/// Budget window. v1 is monthly-only but stored so v2 can add others.
enum BudgetPeriod { monthly }

/// 'YYYY-MM' key a budget row is scoped to (also the family key for budget
/// providers — a String avoids DateTime equality footguns across rebuilds).
String monthKeyFor(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';

/// Populates `external_id` for any row still missing one (pre-v7 rows,
/// backfilled by the v7 migration). Not private — exposed so this behavior
/// can be unit tested directly rather than only through a simulated
/// ALTER TABLE upgrade path.
Future<void> backfillExternalIds(GeneratedDatabase db) async {
  for (final table in ['categories', 'expenses', 'tags', 'budgets']) {
    final rows = await db
        .customSelect('SELECT id FROM $table WHERE external_id IS NULL')
        .get();
    for (final row in rows) {
      await db.customStatement('UPDATE $table SET external_id = ? WHERE id = ?', [
        generateExternalId(),
        row.data['id'],
      ]);
    }
  }
}

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text()(); // emoji glyph, e.g. 🍔
  IntColumn get colorValue => integer()(); // ARGB int
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  /// Excluded from daily/budget totals, top categories, and top expenses —
  /// for fixed costs like rent/EMI. Still shown in transaction lists/exports.
  BoolColumn get isIgnoredForBudget =>
      boolean().withDefault(const Constant(false))();

  /// Stable cross-device/cross-backup identity — see `docs/backup-schema.md`.
  /// Nullable because pre-v7 rows only get one via the v7 migration's
  /// backfill; every new row gets one automatically via [clientDefault].
  TextColumn get externalId =>
      text().nullable().clientDefault(generateExternalId)();
}

@DataClassName('ExpenseRow')
@TableIndex(name: 'idx_expenses_date', columns: {#date})
@TableIndex(name: 'idx_expenses_category', columns: {#categoryId})
@TableIndex(name: 'idx_expenses_tag', columns: {#tagId})
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Amount in minor units (paise/cents) — decimal-safe, never a float.
  IntColumn get amountMinor => integer()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurrence => textEnum<Recurrence>().nullable()();

  /// Optional grouping across categories (e.g. a vacation trip) — orthogonal
  /// to [categoryId], which an expense keeps regardless of its tag.
  IntColumn get tagId => integer().nullable().references(Tags, #id)();

  /// ISO 4217 code this expense was actually paid in, or null for a
  /// home-currency expense. Always set together with [fxAmountMinor] — never
  /// one without the other.
  TextColumn get fxCurrency => text().nullable()();

  /// Original amount in [fxCurrency] minor units — a receipt, for display
  /// only. [amountMinor] holds the converted home-currency amount and stays
  /// the single source of truth for every total.
  ///
  /// ponytail: two-decimal minor units for every currency, so JPY stores
  /// 150000 for ¥1500 and formatting drops the digits it doesn't use. Add a
  /// per-currency exponent table only if a real 3-decimal case turns up.
  IntColumn get fxAmountMinor => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Stable cross-device/cross-backup identity — see `docs/backup-schema.md`.
  TextColumn get externalId =>
      text().nullable().clientDefault(generateExternalId)();
}

/// User-defined grouping for expenses (trips, home renovation, ...) —
/// orthogonal to [Categories]. See [Expenses.tagId].
@DataClassName('TagRow')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get colorValue => integer()(); // ARGB int
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// ISO 4217 code for a trip abroad; null = an ordinary tag. Expenses tagged
  /// with this are entered in this currency and converted on save.
  TextColumn get fxCurrency => text().nullable()();

  /// Home-currency units per 1 unit of [fxCurrency], scaled by 1e6
  /// (2.62 INR per THB is stored as 2_620_000). Integer so a rate never rides
  /// a double. See `lib/core/money/fx.dart`.
  IntColumn get fxRateMicros => integer().nullable()();

  /// Trip date range for auto-tagging (inclusive, date-only — time of day is
  /// ignored). Both null = no auto-tagging. Independent of [fxCurrency] — a
  /// domestic trip can use this without ever touching the currency switch.
  /// Always set together; never one without the other.
  DateTimeColumn get tripStartDate => dateTime().nullable()();
  DateTimeColumn get tripEndDate => dateTime().nullable()();

  /// Stable cross-device/cross-backup identity — see `docs/backup-schema.md`.
  TextColumn get externalId =>
      text().nullable().clientDefault(generateExternalId)();
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null = overall monthly budget; set = per-category budget.
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get period =>
      textEnum<BudgetPeriod>().withDefault(const Constant('monthly'))();

  /// 'YYYY-MM' — which month this budget applies to. See [monthKeyFor].
  TextColumn get monthKey => text()();

  /// Stable cross-device/cross-backup identity — see `docs/backup-schema.md`.
  TextColumn get externalId =>
      text().nullable().clientDefault(generateExternalId)();
}

/// Typed key/value app settings: theme mode, currency locale, auto-backup
/// frequency, last-backup timestamp/size. One row per key.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Categories, Expenses, Budgets, Settings, Tags])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// In-memory database for tests — no files touched.
  AppDatabase.forTesting(super.executor);

  /// Bump this whenever the schema changes, and add the matching
  /// `if (from < N)` block below. Before merging, extend
  /// test/migration_test.dart's seeded v1 database with a row exercising the
  /// new block, and re-run it — `onUpgrade` steps that use a "live schema"
  /// helper (`m.createTable`, `insertAll`/Companions with a `clientDefault`
  /// column) instead of raw SQL scoped to the historical shape have broken
  /// three times already for exactly this reason (see the fixes this comment
  /// shipped with).
  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await batch((b) => b.insertAll(categories, _defaultCategories));
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Budgets used to be a single standing row per category; scope the
        // pre-existing ones onto the current month so they keep working.
        //
        // Raw ALTER, not m.addColumn: SQLite rejects ADD COLUMN ... NOT NULL
        // with no default on a table that already has rows (fine on an empty
        // table, fails the moment there's one — caught by
        // test/migration_test.dart). Nullable at the DDL level; the UPDATE
        // right below immediately backfills every row to a real value.
        await customStatement('ALTER TABLE budgets ADD COLUMN month_key TEXT');
        await customStatement(
          'UPDATE budgets SET month_key = ? WHERE month_key IS NULL',
          [monthKeyFor(DateTime.now())],
        );
      }
      if (from < 3) {
        // New default categories added post-launch; append to existing
        // installs instead of only seeding them on fresh installs/reset.
        //
        // Raw INSERT, not b.insertAll(categories, _newCategoriesV3):
        // CategoriesCompanion.insert always writes every current column via
        // clientDefault, including external_id — which doesn't exist yet
        // for anyone upgrading from below v7 (added at from<7). Caught by
        // test/migration_test.dart.
        final newCategories = _defaultCategorySpecs.skip(8).toList();
        for (var i = 0; i < newCategories.length; i++) {
          final spec = newCategories[i];
          await customStatement(
            'INSERT INTO categories (name, icon, color_value, sort_order, is_default) '
            'VALUES (?, ?, ?, ?, 1)',
            [spec.$1, spec.$2, spec.$3, 8 + i],
          );
        }
      }
      if (from < 4) {
        // Trip/tag grouping — additive, no data migration needed.
        await m.createTable(tags);
        await m.addColumn(expenses, expenses.tagId);
      }
      if (from < 5) {
        // Index the columns every expense query filters/sorts on — existing
        // installs were doing full table scans. Fresh installs get these via
        // @TableIndex + createAll.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_tag ON expenses(tag_id)',
        );
      }
      if (from < 6) {
        await m.addColumn(categories, categories.isIgnoredForBudget);
      }
      if (from < 7) {
        // Stable cross-device/cross-backup identity, replacing name/
        // fingerprint-only matching in backup Merge (docs/backup-schema.md).
        await m.addColumn(categories, categories.externalId);
        await m.addColumn(expenses, expenses.externalId);
        // m.createTable always builds the *current* table definition, so
        // anyone upgrading from below v4 got `tags` created above (from<4)
        // with external_id already on it — adding it again here would be a
        // duplicate-column error. Caught by test/migration_test.dart.
        if (!await _hasColumn('tags', 'external_id')) {
          await m.addColumn(tags, tags.externalId);
        }
        await m.addColumn(budgets, budgets.externalId);
        await backfillExternalIds(this);
      }
      if (from < 8) {
        // Foreign-currency spending on trips. All four nullable with no
        // default, so ADD COLUMN is safe on a populated table and existing
        // rows need no backfill — null means "home currency", which is what
        // every pre-v8 expense and tag already was.
        await m.addColumn(expenses, expenses.fxCurrency);
        await m.addColumn(expenses, expenses.fxAmountMinor);
        // Same createTable trap as external_id above: `tags` is built from
        // the current definition at from<4, so a pre-v4 install already has
        // these two. Caught by test/migration_test.dart.
        if (!await _hasColumn('tags', 'fx_currency')) {
          await m.addColumn(tags, tags.fxCurrency);
          await m.addColumn(tags, tags.fxRateMicros);
        }
      }
      if (from < 9) {
        // Trip date-range auto-tagging. Same createTable trap as above —
        // guard before adding to `tags`.
        if (!await _hasColumn('tags', 'trip_start_date')) {
          await m.addColumn(tags, tags.tripStartDate);
          await m.addColumn(tags, tags.tripEndDate);
        }
      }
    },
  );

  /// Whether [table] already has [column], by its snake_case SQL name.
  ///
  /// Needed because `m.createTable` always emits the CURRENT table
  /// definition: a table created by an earlier migration step already carries
  /// every column added since, so a later `addColumn` for one of them would
  /// fail with "duplicate column name". Has bitten `tags` twice now (v7's
  /// external_id, v8's fx columns) — both caught by test/migration_test.dart.
  Future<bool> _hasColumn(String table, String column) async {
    final columns = await customSelect('PRAGMA table_info($table)').get();
    return columns.any((row) => row.data['name'] == column);
  }

  /// Wipes expenses/budgets/categories/settings (profile, theme, prefs — all
  /// of it) and re-seeds the default categories, matching a fresh install.
  /// Never touches backup files — those live outside this database.
  Future<void> resetToDefaults() async {
    await transaction(() async {
      // Children before parents (FK order), same as BackupRepository.replaceAll.
      await delete(expenses).go();
      await delete(tags).go();
      await delete(budgets).go();
      await delete(categories).go();
      await delete(settings).go();
      await batch((b) => b.insertAll(categories, _defaultCategories));
    });
  }

  static LazyDatabase _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'spendly.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}

/// Ships-with-the-app categories (FR-8). Icons + colors match the prototype.
/// First 8 shipped in v1; the rest were added in schema v3 and are also
/// backfilled onto existing installs via [_newCategoriesV3] (see migration).
const _defaultCategorySpecs = <(String, String, int)>[
  ('Food', '🍔', 0xFF6366F1), // primary
  ('Travel', '🚕', 0xFFF59E0B), // accent
  ('Shopping', '🛒', 0xFF6366F1), // primary
  ('Bills', '🧾', 0xFF14B8A6), // teal
  ('Entertainment', '🎬', 0xFFEC4899), // pink
  ('Health', '💊', 0xFF14B8A6), // teal
  ('Home', '🏠', 0xFF6366F1), // primary
  ('Other', '📦', 0xFF6B6B7B), // text-dim
  ('EMI / Loan', '🏦', 0xFF4F46E5), // primaryDeep
  ('Online Shopping', '🛍️', 0xFFEC4899), // pink
  ('Groceries', '🍎', 0xFF14B8A6), // teal
  ('Fuel', '⛽', 0xFFF59E0B), // accent
  ('Insurance', '🛡️', 0xFF6366F1), // primary
  ('Subscriptions', '📺', 0xFFEC4899), // pink
  ('Education', '🎓', 0xFF818CF8), // primarySoft
  ('Personal Care', '🧴', 0xFF14B8A6), // teal
  ('Fitness', '🏋️', 0xFFF59E0B), // accent
  ('Gifts & Donations', '🎁', 0xFF6366F1), // primary
];

List<CategoriesCompanion> _categoriesFrom(
  List<(String, String, int)> specs, {
  int startIndex = 0,
}) {
  return [
    for (var i = 0; i < specs.length; i++)
      CategoriesCompanion.insert(
        name: specs[i].$1,
        icon: specs[i].$2,
        colorValue: specs[i].$3,
        sortOrder: Value(startIndex + i),
        isDefault: const Value(true),
      ),
  ];
}

final List<CategoriesCompanion> _defaultCategories = _categoriesFrom(
  _defaultCategorySpecs,
);

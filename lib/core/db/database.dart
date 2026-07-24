import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text()(); // emoji glyph, e.g. 🍔
  IntColumn get colorValue => integer()(); // ARGB int
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

@DataClassName('ExpenseRow')
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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
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

@DriftDatabase(tables: [Categories, Expenses, Budgets, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// In-memory database for tests — no files touched.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

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
        await m.addColumn(budgets, budgets.monthKey);
        await customStatement(
          'UPDATE budgets SET month_key = ? WHERE month_key IS NULL',
          [monthKeyFor(DateTime.now())],
        );
      }
    },
  );

  /// Wipes expenses/budgets/categories/settings (profile, theme, prefs — all
  /// of it) and re-seeds the default categories, matching a fresh install.
  /// Never touches backup files — those live outside this database.
  Future<void> resetToDefaults() async {
    await transaction(() async {
      // Children before parents (FK order), same as BackupRepository.replaceAll.
      await delete(expenses).go();
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
final List<CategoriesCompanion> _defaultCategories = () {
  const specs = <(String, String, int)>[
    ('Food', '🍔', 0xFF6366F1), // primary
    ('Travel', '🚕', 0xFFF59E0B), // accent
    ('Shopping', '🛒', 0xFF6366F1), // primary
    ('Bills', '🧾', 0xFF14B8A6), // teal
    ('Entertainment', '🎬', 0xFFEC4899), // pink
    ('Health', '💊', 0xFF14B8A6), // teal
    ('Home', '🏠', 0xFF6366F1), // primary
    ('Other', '📦', 0xFF6B6B7B), // text-dim
  ];
  return [
    for (var i = 0; i < specs.length; i++)
      CategoriesCompanion.insert(
        name: specs[i].$1,
        icon: specs[i].$2,
        colorValue: specs[i].$3,
        sortOrder: Value(i),
        isDefault: const Value(true),
      ),
  ];
}();

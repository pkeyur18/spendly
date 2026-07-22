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
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get period =>
      textEnum<BudgetPeriod>().withDefault(const Constant('monthly'))();
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // ponytail: no migrations yet at v1. Add stepwise upgrades here as
          // schemaVersion bumps; every future version must read old backups.
        },
      );

  static LazyDatabase _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'spendly.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}

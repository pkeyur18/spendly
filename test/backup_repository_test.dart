import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/backup/backup_format.dart';
import 'package:spendly/features/backup/backup_models.dart';
import 'package:spendly/features/backup/backup_repository.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/tags/tag_repository.dart';

void main() {
  late AppDatabase db;
  late BackupRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BackupRepository(db);
  });
  tearDown(() {
    db.close();
  });

  test(
    'export then replace into a fresh db reproduces identical data',
    () async {
      final catRepo = CategoryRepository(db);
      final expRepo = ExpenseRepository(db);
      final budgetRepo = BudgetRepository(db);

      final catId = await catRepo.create(
        name: 'Extra',
        icon: '⭐',
        colorValue: 0xFF6366F1,
      );
      await expRepo.add(
        amount: Money.parse('24.50'),
        categoryId: catId,
        date: DateTime(2026, 7, 1),
      );
      await budgetRepo.setOverall(DateTime(2026, 7, 1), Money.parse('40000'));

      final payload = await repo.exportAll();

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      final freshRepo = BackupRepository(freshDb);
      await freshRepo.replaceAll(payload);

      final reExported = await freshRepo.exportAll();
      expect(reExported.categories.length, payload.categories.length);
      expect(reExported.expenses.length, payload.expenses.length);
      expect(reExported.budgets.length, payload.budgets.length);
      expect(
        reExported.expenses.single.amountMinor,
        Money.parse('24.50').minor,
      );
      await freshDb.close();
    },
  );

  test(
    'merge into a freshly-seeded db does not duplicate the defaults',
    () async {
      final payload = await repo
          .exportAll(); // default categories, nothing else

      await repo.mergeAll(payload);

      final categories = await db.select(db.categories).get();
      expect(categories.length, 18); // still 18, not 36
    },
  );

  test(
    'merging the same backup twice does not duplicate expenses or budgets',
    () async {
      // A separate source device's data, exported once, then merged into
      // `db` (fresh, 8-default) twice — the second merge must be a no-op.
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await ExpenseRepository(sourceDb).add(
        amount: Money.parse('100'),
        categoryId: 1,
        date: DateTime(2026, 7, 5),
      );
      await BudgetRepository(
        sourceDb,
      ).setForCategory(DateTime(2026, 7, 1), 1, Money.parse('5000'));
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);
      await repo.mergeAll(payload); // run twice

      final expenses = await db.select(db.expenses).get();
      final budgets = await db.select(db.budgets).get();
      expect(expenses.length, 1); // not duplicated on the repeat merge
      expect(budgets.length, 1);
    },
  );

  test(
    'merge still adds genuinely new categories, expenses and budgets',
    () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final sourceCatRepo = CategoryRepository(sourceDb);
      final sourceExpRepo = ExpenseRepository(sourceDb);
      final newCatId = await sourceCatRepo.create(
        name: 'Brand New',
        icon: '🆕',
        colorValue: 0xFF14B8A6,
      );
      await sourceExpRepo.add(
        amount: Money.parse('75'),
        categoryId: newCatId,
        date: DateTime(2026, 7, 10),
      );
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload); // into the fresh 8-default db

      final categories = await db.select(db.categories).get();
      final expenses = await db.select(db.expenses).get();
      expect(categories.any((c) => c.name == 'Brand New'), isTrue);
      expect(expenses.length, 1);
      expect(expenses.single.amountMinor, Money.parse('75').minor);
    },
  );

  test('replace fully wipes prior data before restoring the backup', () async {
    final expRepo = ExpenseRepository(db);
    await expRepo.add(
      amount: Money.parse('999'),
      categoryId: 1,
      date: DateTime(2026, 1, 1),
    );

    final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
    await ExpenseRepository(
      sourceDb,
    ).add(amount: Money.parse('50'), categoryId: 1, date: DateTime(2026, 7, 1));
    final payload = await BackupRepository(sourceDb).exportAll();
    await sourceDb.close();

    await repo.replaceAll(payload);

    final expenses = await db.select(db.expenses).get();
    expect(expenses.length, 1);
    expect(
      expenses.single.amountMinor,
      Money.parse('50').minor,
    ); // the ₹999 row is gone
  });

  test(
    'export includes the profile photo as an ordinary setting; replace restores identical bytes',
    () async {
      final photoBytes = utf8.encode('fake jpeg bytes');
      await SettingsRepository(db).set(
        SettingsRepository.profilePhotoBase64Key,
        base64Encode(photoBytes),
      );
      await SettingsRepository(
        db,
      ).set(SettingsRepository.profileNameKey, 'Ada');

      final payload = await repo.exportAll();
      expect(
        payload.settings.singleWhere(
          (s) => s.key == SettingsRepository.profilePhotoBase64Key,
        ).value,
        base64Encode(photoBytes),
      );
      expect(
        payload.settings.any((s) => s.key == SettingsRepository.profileNameKey),
        isTrue,
      );

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      await BackupRepository(freshDb).replaceAll(payload);

      final restoredBase64 = await SettingsRepository(
        freshDb,
      ).get(SettingsRepository.profilePhotoBase64Key);
      expect(restoredBase64, base64Encode(photoBytes));
      await freshDb.close();
    },
  );

  test(
    'replace with no photo in the payload leaves photo state wiped',
    () async {
      final payload = await repo.exportAll(); // no photo ever set

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      await BackupRepository(freshDb).replaceAll(payload);
      final restoredBase64 = await SettingsRepository(
        freshDb,
      ).get(SettingsRepository.profilePhotoBase64Key);
      expect(restoredBase64, isNull); // falls back to colored initials (FR-55)
      await freshDb.close();
    },
  );

  test(
    'merge never restores the profile photo, same as other settings',
    () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final photoBytes = utf8.encode('another fake jpeg');
      await SettingsRepository(sourceDb).set(
        SettingsRepository.profilePhotoBase64Key,
        base64Encode(photoBytes),
      );
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);

      final restoredBase64 = await SettingsRepository(
        db,
      ).get(SettingsRepository.profilePhotoBase64Key);
      expect(restoredBase64, isNull);
    },
  );

  test(
    'export then replace into a fresh db preserves tags and expense.tagId',
    () async {
      final tagRepo = TagRepository(db);
      final expRepo = ExpenseRepository(db);
      final tagId = await tagRepo.create(
        name: 'Japan Trip',
        colorValue: 0xFF6366F1,
      );
      await expRepo.add(
        amount: Money.parse('100'),
        categoryId: 1,
        date: DateTime(2026, 7, 1),
        tagId: tagId,
      );
      await expRepo.add(
        amount: Money.parse('50'),
        categoryId: 1,
        date: DateTime(2026, 7, 2),
      ); // untagged

      final payload = await repo.exportAll();
      expect(payload.tags.single.name, 'Japan Trip');

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      await BackupRepository(freshDb).replaceAll(payload);

      final tags = await freshDb.select(freshDb.tags).get();
      final expenses = await freshDb.select(freshDb.expenses).get();
      expect(tags.single.name, 'Japan Trip');
      expect(
        expenses.firstWhere((e) => e.amountMinor == 10000).tagId,
        tags.single.id,
      );
      expect(expenses.firstWhere((e) => e.amountMinor == 5000).tagId, isNull);
      await freshDb.close();
    },
  );

  test('merging the same backup twice does not duplicate tags, and maps '
      'tagged expenses onto the local tag', () async {
    final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceTagId = await TagRepository(
      sourceDb,
    ).create(name: 'Japan Trip', colorValue: 0xFF6366F1);
    await ExpenseRepository(sourceDb).add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 7, 5),
      tagId: sourceTagId,
    );
    final payload = await BackupRepository(sourceDb).exportAll();
    await sourceDb.close();

    await repo.mergeAll(payload);
    await repo.mergeAll(payload); // run twice

    final tags = await db.select(db.tags).get();
    final expenses = await db.select(db.expenses).get();
    expect(tags.length, 1); // not duplicated on the repeat merge
    expect(expenses.single.tagId, tags.single.id);
  });

  test(
    'renaming a category then merging the original backup matches by '
    'externalId, not by name — no duplicate, rename preserved',
    () async {
      final catRepo = CategoryRepository(db);
      final before = await db.select(db.categories).get();
      final target = before.first;

      final payload = await repo.exportAll(); // snapshot before the rename

      await catRepo.rename(target.id, 'Renamed Category');
      await repo.mergeAll(payload); // merge the pre-rename backup back in

      final after = await db.select(db.categories).get();
      expect(after.length, before.length); // no duplicate inserted
      expect(after.any((c) => c.name == 'Renamed Category'), isTrue);
      expect(after.any((c) => c.name == target.name), isFalse);
    },
  );

  test(
    'merging a legacy backup with no externalId field at all still falls '
    'back to name matching, unchanged',
    () async {
      final before = await db.select(db.categories).get();
      final target = before.first;

      // Hand-built payload simulating a pre-this-change export: no
      // "externalId" key on the category at all (not even null).
      final legacyJson = {
        'exportedAt': DateTime.now().toIso8601String(),
        'categories': [
          {
            'id': target.id,
            'name': target.name,
            'icon': target.icon,
            'colorValue': target.colorValue,
            'sortOrder': target.sortOrder,
            'isArchived': target.isArchived,
            'isDefault': target.isDefault,
            'isIgnoredForBudget': target.isIgnoredForBudget,
          },
        ],
        'expenses': [],
        'budgets': [],
        'settings': [],
        'tags': [],
      };
      final payload = BackupPayload.fromJson(legacyJson);

      await repo.mergeAll(payload);

      final after = await db.select(db.categories).get();
      expect(after.length, before.length); // matched by name, not duplicated
    },
  );

  test(
    'importing a corrupted file leaves all existing data untouched',
    () async {
      final expRepo = ExpenseRepository(db);
      await expRepo.add(
        amount: Money.parse('123'),
        categoryId: 1,
        date: DateTime(2026, 3, 1),
      );

      final categoriesBefore = (await db.select(db.categories).get()).length;
      final expensesBefore = (await db.select(db.expenses).get()).length;
      final budgetsBefore = (await db.select(db.budgets).get()).length;

      // decodePayload is the full FR-41 validation gate `loadAndValidate` runs
      // before ever touching the repository — it must throw here, before any
      // DB write is attempted.
      await expectLater(
        () => decodePayload('not valid json {{{'),
        throwsA(isA<BackupCorruptException>()),
      );

      expect((await db.select(db.categories).get()).length, categoriesBefore);
      expect((await db.select(db.expenses).get()).length, expensesBefore);
      expect((await db.select(db.budgets).get()).length, budgetsBefore);
    },
  );
}

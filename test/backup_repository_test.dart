import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/backup/backup_format.dart';
import 'package:spendly/features/backup/backup_models.dart';
import 'package:spendly/features/accounts/account_repository.dart';
import 'package:spendly/features/backup/backup_repository.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/expenses/receipt_repository.dart';
import 'package:spendly/features/goals/goal_repository.dart';
import 'package:spendly/features/ledger/ledger_repository.dart';
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

  group('receipt photos', () {
    test('export then replace reattaches the receipt to the same expense',
        () async {
      final expRepo = ExpenseRepository(db);
      final receiptRepo = ReceiptRepository(db);
      final expenseId = await expRepo.add(
        amount: Money.parse('240'),
        categoryId: 1,
        date: DateTime(2026, 7, 1),
      );
      await receiptRepo.set(expenseId, Uint8List.fromList([9, 8, 7]));

      final payload = await repo.exportAll();
      expect(payload.receipts, hasLength(1));

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      final restoredExpense = (await freshDb.select(freshDb.expenses).get())
          .single;
      final restoredPhoto = await ReceiptRepository(
        freshDb,
      ).forExpense(restoredExpense.id);
      // Not just "a receipt exists somewhere" — it must be attached to THIS
      // expense, and Replace's whole safety argument is that reused ids line
      // up exactly, so this is the assertion that actually tests that.
      expect(restoredPhoto, [9, 8, 7]);
    });

    test('an expense with no receipt restores with no receipt', () async {
      await ExpenseRepository(
        db,
      ).add(amount: Money.parse('50'), categoryId: 1);
      final payload = await repo.exportAll();
      expect(payload.receipts, isEmpty);

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      expect(await freshDb.select(freshDb.expenseReceipts).get(), isEmpty);
    });

    test('replace clears a receipt that existed only on the restoring device',
        () async {
      // The receiving device has its own photo attached to expense #1; the
      // backup has none for its own expense #1. Replace wipes first, so the
      // stale local photo must not survive.
      final localId = await ExpenseRepository(
        db,
      ).add(amount: Money.parse('10'), categoryId: 1);
      await ReceiptRepository(db).set(localId, Uint8List.fromList([1]));

      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await ExpenseRepository(
        sourceDb,
      ).add(amount: Money.parse('10'), categoryId: 1);
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.replaceAll(payload);

      expect(await db.select(db.expenseReceipts).get(), isEmpty);
    });

    test('merge attaches a receipt to a newly-inserted expense', () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final sourceExpenseId = await ExpenseRepository(sourceDb).add(
        amount: Money.parse('75'),
        categoryId: 1,
        date: DateTime(2026, 7, 10),
      );
      await ReceiptRepository(
        sourceDb,
      ).set(sourceExpenseId, Uint8List.fromList([4, 4, 4]));
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload); // into the fresh 8-default db

      final expenses = await db.select(db.expenses).get();
      expect(expenses, hasLength(1));
      // The merged expense's LOCAL id was assigned fresh — it is not the
      // source device's id — so this is the assertion that the receipt
      // followed the right row through that remapping, not just that a
      // receipt exists somewhere in the table.
      final photo = await ReceiptRepository(
        db,
      ).forExpense(expenses.single.id);
      expect(photo, [4, 4, 4]);
    });

    test('merge never overwrites a receipt already on a matched expense',
        () async {
      // Same expense on both sides (matched by content fingerprint, no
      // externalId yet); the backup carries a DIFFERENT photo for it. Merge
      // must not touch the local one — matched rows are never updated by
      // merge, on any field, and a receipt is no exception.
      final localId = await ExpenseRepository(db).add(
        amount: Money.parse('30'),
        categoryId: 1,
        date: DateTime(2026, 7, 2),
        note: 'Taxi',
      );
      await ReceiptRepository(db).set(localId, Uint8List.fromList([1]));

      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final sourceExpenseId = await ExpenseRepository(sourceDb).add(
        amount: Money.parse('30'),
        categoryId: 1,
        date: DateTime(2026, 7, 2),
        note: 'Taxi',
      );
      await ReceiptRepository(
        sourceDb,
      ).set(sourceExpenseId, Uint8List.fromList([2, 2]));
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);

      expect(await db.select(db.expenses).get(), hasLength(1));
      expect(await ReceiptRepository(db).forExpense(localId), [1]);
    });

    test('a pre-v7 backup (no receipts key) merges with no receipts at all',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await ExpenseRepository(
        sourceDb,
      ).add(amount: Money.parse('20'), categoryId: 1, date: DateTime(2026, 7, 3));
      final exported = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();
      final preV7 = BackupPayload(
        exportedAt: exported.exportedAt,
        categories: exported.categories,
        expenses: exported.expenses,
        budgets: exported.budgets,
        settings: exported.settings,
        tags: exported.tags,
        // No `receipts:` — defaults to const [], matching a decoded pre-v7
        // JSON file that never had the key at all.
      );

      await repo.mergeAll(preV7);

      expect(await db.select(db.expenses).get(), hasLength(1));
      expect(await db.select(db.expenseReceipts).get(), isEmpty);
    });
  });

  group('accounts', () {
    test('export then replace reattaches the account to the same expense',
        () async {
      final accountRepo = AccountRepository(db);
      final accountId = await accountRepo.create(
        name: 'HDFC Bank',
        type: AccountType.bank,
        openingBalance: Money.parse('1000'),
      );
      final expenseId = await ExpenseRepository(db).add(
        amount: Money.parse('240'),
        categoryId: 1,
        date: DateTime(2026, 7, 1),
        accountId: accountId,
      );

      final payload = await repo.exportAll();
      expect(payload.accounts, hasLength(1));

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      final restoredExpense = (await freshDb.select(freshDb.expenses).get())
          .firstWhere((e) => e.id == expenseId);
      final restoredAccount = await (freshDb.select(
        freshDb.accounts,
      )..where((t) => t.id.equals(restoredExpense.accountId!))).getSingle();
      expect(restoredAccount.name, 'HDFC Bank');
      expect(restoredAccount.openingBalanceMinor, Money.parse('1000').minor);
    });

    test('merge attaches an account to a newly-inserted expense under its '
        'new local id', () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final sourceAccountId = await AccountRepository(sourceDb).create(
        name: 'Wallet',
        type: AccountType.wallet,
      );
      await ExpenseRepository(sourceDb).add(
        amount: Money.parse('75'),
        categoryId: 1,
        date: DateTime(2026, 7, 10),
        accountId: sourceAccountId,
      );
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload); // into the fresh 8-default db

      final accounts = await db.select(db.accounts).get();
      final expenses = await db.select(db.expenses).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.name, 'Wallet');
      // The merged expense's account id was assigned fresh by THIS device —
      // it must not equal the source device's id, and it must point at the
      // account that actually landed here.
      expect(expenses.single.accountId, accounts.single.id);
    });

    test('merging the same backup twice does not duplicate the account',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await AccountRepository(sourceDb).create(name: 'Cash', type: AccountType.cash);
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);
      await repo.mergeAll(payload); // run twice

      expect(await db.select(db.accounts).get(), hasLength(1));
    });

    test('renaming an account then merging the original backup matches by '
        'externalId, keeps the rename, does not duplicate', () async {
      final accountRepo = AccountRepository(db);
      final id = await accountRepo.create(name: 'Old Name', type: AccountType.cash);
      final payload = await repo.exportAll(); // carries externalId + 'Old Name'
      await accountRepo.update(id, name: 'New Name');

      await repo.mergeAll(payload);

      final accounts = await db.select(db.accounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.name, 'New Name'); // untouched by the merge
    });

    test('a pre-v8 backup (no accounts key) merges with no accounts at all',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await ExpenseRepository(
        sourceDb,
      ).add(amount: Money.parse('20'), categoryId: 1, date: DateTime(2026, 7, 3));
      final exported = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();
      final preV8 = BackupPayload(
        exportedAt: exported.exportedAt,
        categories: exported.categories,
        expenses: exported.expenses,
        budgets: exported.budgets,
        settings: exported.settings,
        tags: exported.tags,
        // No `accounts:` — defaults to const [].
      );

      await repo.mergeAll(preV8);

      expect(await db.select(db.expenses).get(), hasLength(1));
      expect(await db.select(db.accounts).get(), isEmpty);
    });

    test('merge carries includeInNetWorth over to a newly-inserted account',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await AccountRepository(sourceDb).create(
        name: 'Car loan',
        type: AccountType.bank,
        includeInNetWorth: false,
      );
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);

      final account = (await db.select(db.accounts).get()).single;
      expect(account.includeInNetWorth, isFalse);
    });

    test('replace restores includeInNetWorth verbatim', () async {
      final accountRepo = AccountRepository(db);
      await accountRepo.create(
        name: 'Car loan',
        type: AccountType.bank,
        includeInNetWorth: false,
      );
      final payload = await repo.exportAll();

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      final restored = (await freshDb.select(freshDb.accounts).get()).single;
      expect(restored.includeInNetWorth, isFalse);
    });

    group('default account', () {
      test('replace restores the backup default verbatim', () async {
        final accountRepo = AccountRepository(db);
        await accountRepo.create(name: 'Cash', type: AccountType.cash);
        final payload = await repo.exportAll();
        expect(payload.accounts.single.isDefault, isTrue);

        final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(freshDb.close);
        await BackupRepository(freshDb).replaceAll(payload);

        expect(
          (await freshDb.select(freshDb.accounts).get()).single.isDefault,
          isTrue,
        );
      });

      test(
        'merge carries the default onto a newly-inserted account when the '
        'local device has none yet',
        () async {
          final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
          await AccountRepository(
            sourceDb,
          ).create(name: 'Cash', type: AccountType.cash); // auto-default
          final payload = await BackupRepository(sourceDb).exportAll();
          await sourceDb.close();

          await repo.mergeAll(payload); // into the fresh 8-default db, no accounts yet

          expect(
            (await db.select(db.accounts).get()).single.isDefault,
            isTrue,
          );
        },
      );

      test(
        'merge never creates a second default when the local device '
        'already has one',
        () async {
          // Local device already has its own default.
          final accountRepo = AccountRepository(db);
          await accountRepo.create(name: 'Local Cash', type: AccountType.cash);

          // Source device's account was ALSO default there.
          final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
          await AccountRepository(
            sourceDb,
          ).create(name: 'Source Wallet', type: AccountType.wallet);
          final payload = await BackupRepository(sourceDb).exportAll();
          await sourceDb.close();

          await repo.mergeAll(payload);

          final accounts = await db.select(db.accounts).get();
          expect(accounts, hasLength(2));
          // The merge must not have promoted the newly-inserted account to
          // default just because the backup said it was on its own device —
          // exactly one default survives, and it's the one that was already
          // here.
          expect(accounts.where((a) => a.isDefault), hasLength(1));
          expect(
            accounts.singleWhere((a) => a.isDefault).name,
            'Local Cash',
          );
        },
      );

      test(
        'merging two new non-default-on-local accounts from a backup with '
        'two defaults still yields exactly one default',
        () async {
          // Contrived but worth pinning: a hand-authored payload where two
          // *different* accounts both claim isDefault — never producible by
          // this app's own UI, but a hostile or corrupted file could claim
          // it, and the merge must not honor both.
          final a = const BackupAccount(
            id: 1,
            name: 'A',
            type: AccountType.cash,
            openingBalanceMinor: 0,
            isArchived: false,
            externalId: null,
            isDefault: true,
          );
          final b = const BackupAccount(
            id: 2,
            name: 'B',
            type: AccountType.bank,
            openingBalanceMinor: 0,
            isArchived: false,
            externalId: null,
            isDefault: true,
          );
          final payload = BackupPayload(
            exportedAt: DateTime(2026, 1, 1),
            categories: const [],
            expenses: const [],
            budgets: const [],
            settings: const [],
            tags: const [],
            accounts: [a, b],
          );

          await repo.mergeAll(payload);

          final accounts = await db.select(db.accounts).get();
          expect(accounts, hasLength(2));
          expect(accounts.where((acc) => acc.isDefault), hasLength(1));
        },
      );

      test('merge never overwrites a matched account\'s default status',
          () async {
        // Local has a default; the backup's matching (same name) account
        // claims isDefault: false. A match is never updated on any field —
        // default status included — so the local default must survive.
        final accountRepo = AccountRepository(db);
        await accountRepo.create(name: 'Cash', type: AccountType.cash);
        final payload = await repo.exportAll();

        await repo.mergeAll(payload);

        expect(
          (await db.select(db.accounts).get()).single.isDefault,
          isTrue,
        );
      });
    });
  });

  group('ledger entries (income)', () {
    test('export then replace reattaches the entry to the same account',
        () async {
      final accountRepo = AccountRepository(db);
      final accountId = await accountRepo.create(
        name: 'HDFC Bank',
        type: AccountType.bank,
      );
      final ledger = LedgerRepository(db);
      final entryId = await ledger.addIncome(
        amount: Money.parse('50000'),
        date: DateTime(2026, 7, 1),
        accountId: accountId,
        sourceLabel: 'Salary',
      );

      final payload = await repo.exportAll();
      expect(payload.ledgerEntries, hasLength(1));

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      final restoredEntry = await (freshDb.select(
        freshDb.ledgerEntries,
      )..where((t) => t.id.equals(entryId))).getSingle();
      final restoredAccount = await (freshDb.select(
        freshDb.accounts,
      )..where((t) => t.id.equals(restoredEntry.accountId!))).getSingle();
      expect(restoredAccount.name, 'HDFC Bank');
      expect(restoredEntry.sourceLabel, 'Salary');
    });

    test('merge attaches an entry to a newly-inserted account under its '
        'new local id', () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final sourceAccountId = await AccountRepository(sourceDb).create(
        name: 'Wallet',
        type: AccountType.wallet,
      );
      await LedgerRepository(sourceDb).addIncome(
        amount: Money.parse('1000'),
        date: DateTime(2026, 7, 10),
        accountId: sourceAccountId,
      );
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload); // into the fresh 8-default db

      final accounts = await db.select(db.accounts).get();
      final entries = await db.select(db.ledgerEntries).get();
      expect(accounts, hasLength(1));
      // The merged entry's account id was assigned fresh by THIS device — it
      // must point at the account that actually landed here.
      expect(entries.single.accountId, accounts.single.id);
    });

    test('merging the same backup twice does not duplicate the entry',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await LedgerRepository(
        sourceDb,
      ).addIncome(amount: Money.parse('500'), date: DateTime(2026, 7, 1));
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);
      await repo.mergeAll(payload); // run twice

      expect(await db.select(db.ledgerEntries).get(), hasLength(1));
    });

    test('a pre-v9 backup (no ledgerEntries key) merges with no ledger '
        'entries at all', () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await ExpenseRepository(
        sourceDb,
      ).add(amount: Money.parse('20'), categoryId: 1, date: DateTime(2026, 7, 3));
      final exported = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();
      final preV9 = BackupPayload(
        exportedAt: exported.exportedAt,
        categories: exported.categories,
        expenses: exported.expenses,
        budgets: exported.budgets,
        settings: exported.settings,
        tags: exported.tags,
        // No `ledgerEntries:` — defaults to const [].
      );

      await repo.mergeAll(preV9);

      expect(await db.select(db.expenses).get(), hasLength(1));
      expect(await db.select(db.ledgerEntries).get(), isEmpty);
    });

    test('merge attaches a transfer to both newly-inserted accounts under '
        'their new local ids', () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      final sourceA = await AccountRepository(
        sourceDb,
      ).create(name: 'Cash', type: AccountType.cash);
      final sourceB = await AccountRepository(
        sourceDb,
      ).create(name: 'Bank', type: AccountType.bank);
      await LedgerRepository(sourceDb).addTransfer(
        amount: Money.parse('300'),
        date: DateTime(2026, 7, 5),
        fromAccountId: sourceA,
        toAccountId: sourceB,
      );
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload); // into the fresh 8-default db

      final accounts = await db.select(db.accounts).get();
      final entry = (await db.select(db.ledgerEntries).get()).single;
      final localA = accounts.firstWhere((a) => a.name == 'Cash');
      final localB = accounts.firstWhere((a) => a.name == 'Bank');
      expect(entry.kind, LedgerEntryKind.transfer);
      expect(entry.accountId, localA.id);
      expect(entry.counterAccountId, localB.id);
    });

    test('export then replace preserves a transfer\'s kind and both accounts',
        () async {
      final accountRepo = AccountRepository(db);
      final a = await accountRepo.create(name: 'Cash', type: AccountType.cash);
      final b = await accountRepo.create(name: 'Bank', type: AccountType.bank);
      await LedgerRepository(db).addTransfer(
        amount: Money.parse('300'),
        date: DateTime(2026, 7, 5),
        fromAccountId: a,
        toAccountId: b,
      );

      final payload = await repo.exportAll();
      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      final entry = (await freshDb.select(freshDb.ledgerEntries).get()).single;
      expect(entry.kind, LedgerEntryKind.transfer);
      expect(entry.accountId, a);
      expect(entry.counterAccountId, b);
    });
  });

  group('savings goals', () {
    test('export then replace preserves saved progress and target', () async {
      final goalRepo = GoalRepository(db);
      final id = await goalRepo.create(
        name: 'New laptop',
        target: Money.parse('80000'),
      );
      await goalRepo.adjustSaved(id, Money.parse('20000'));

      final payload = await repo.exportAll();
      expect(payload.savingsGoals, hasLength(1));

      final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDb.close);
      await BackupRepository(freshDb).replaceAll(payload);

      final restored = (await freshDb.select(freshDb.savingsGoals).get()).single;
      expect(restored.name, 'New laptop');
      expect(restored.targetMinor, Money.parse('80000').minor);
      expect(restored.savedMinor, Money.parse('20000').minor);
    });

    test('merging the same backup twice does not duplicate the goal',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await GoalRepository(
        sourceDb,
      ).create(name: 'Emergency fund', target: Money.parse('50000'));
      final payload = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();

      await repo.mergeAll(payload);
      await repo.mergeAll(payload); // run twice

      expect(await db.select(db.savingsGoals).get(), hasLength(1));
    });

    test('renaming a goal then merging the original backup matches by '
        'externalId, keeps the rename, does not duplicate', () async {
      final goalRepo = GoalRepository(db);
      final id = await goalRepo.create(
        name: 'Old name',
        target: Money.parse('1000'),
      );
      final payload = await repo.exportAll(); // carries externalId + 'Old name'
      await goalRepo.update(id, name: 'New name');

      await repo.mergeAll(payload);

      final goals = await db.select(db.savingsGoals).get();
      expect(goals, hasLength(1));
      expect(goals.single.name, 'New name'); // untouched by the merge
    });

    test('a pre-v10 backup (no savingsGoals key) merges with no goals at all',
        () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      await ExpenseRepository(
        sourceDb,
      ).add(amount: Money.parse('20'), categoryId: 1, date: DateTime(2026, 7, 3));
      final exported = await BackupRepository(sourceDb).exportAll();
      await sourceDb.close();
      final preV10 = BackupPayload(
        exportedAt: exported.exportedAt,
        categories: exported.categories,
        expenses: exported.expenses,
        budgets: exported.budgets,
        settings: exported.settings,
        tags: exported.tags,
        // No `savingsGoals:` — defaults to const [].
      );

      await repo.mergeAll(preV10);

      expect(await db.select(db.expenses).get(), hasLength(1));
      expect(await db.select(db.savingsGoals).get(), isEmpty);
    });
  });
}

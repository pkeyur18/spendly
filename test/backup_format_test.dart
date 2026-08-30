import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/backup/backup_format.dart';
import 'package:spendly/features/backup/backup_models.dart';

BackupPayload _samplePayload() => BackupPayload(
  exportedAt: DateTime(2026, 7, 23, 10, 15),
  categories: [
    const BackupCategory(
      id: 1,
      name: 'Food',
      icon: '🍔',
      colorValue: 0xFF6366F1,
      sortOrder: 0,
      isArchived: false,
      isDefault: true,
      isIgnoredForBudget: false,
      externalId: null,
    ),
  ],
  expenses: [
    BackupExpense(
      id: 1,
      amountMinor: 24500,
      categoryId: 1,
      date: DateTime(2026, 7, 1),
      note: 'Groceries',
      paymentMethod: 'UPI',
      isRecurring: false,
      recurrence: null,
      nextDueDate: null,
      recurrenceEndDate: null,
      tagId: 1,
      accountId: null,
      createdAt: DateTime(2026, 7, 1, 9, 3),
      updatedAt: DateTime(2026, 7, 1, 9, 3),
      externalId: null,
      // Foreign receipt (v4): ¥45,000 that converted to the ₹245.00 above.
      fxCurrency: 'JPY',
      fxAmountMinor: 4500000,
    ),
  ],
  tags: [
    BackupTag(
      id: 1,
      name: 'Japan Trip',
      colorValue: 0xFF6366F1,
      isArchived: false,
      externalId: null,
      fxCurrency: 'JPY',
      fxRateMicros: 550000,
      tripStartDate: DateTime(2026, 7, 1),
      tripEndDate: DateTime(2026, 7, 10),
    ),
  ],
  budgets: const [
    BackupBudget(
      id: 1,
      categoryId: null,
      amountMinor: 5000000,
      period: BudgetPeriod.monthly,
      monthKey: '2026-07',
      externalId: null,
    ),
  ],
  settings: const [BackupSetting(key: 'theme_mode', value: 'system')],
);

void main() {
  test('plain round trip decodes to an identical payload', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(payload);
    final decoded = await decodePayload(envelope);
    expect(jsonEncode(decoded.toJson()), jsonEncode(payload.toJson()));
  });

  test(
    'encrypted round trip with the correct password decodes identically',
    () async {
      final payload = _samplePayload();
      final envelope = await encodeEnvelope(payload, password: 'hunter2');
      final decoded = await decodePayload(envelope, password: 'hunter2');
      expect(jsonEncode(decoded.toJson()), jsonEncode(payload.toJson()));
    },
  );

  test(
    'encrypted file without a password throws BackupPasswordRequiredException',
    () async {
      final envelope = await encodeEnvelope(
        _samplePayload(),
        password: 'hunter2',
      );
      expect(
        () => decodePayload(envelope),
        throwsA(isA<BackupPasswordRequiredException>()),
      );
    },
  );

  test('wrong password throws BackupWrongPasswordException', () async {
    final envelope = await encodeEnvelope(
      _samplePayload(),
      password: 'hunter2',
    );
    expect(
      () => decodePayload(envelope, password: 'wrong'),
      throwsA(isA<BackupWrongPasswordException>()),
    );
  });

  test('non-JSON text throws BackupCorruptException', () async {
    expect(
      () => decodePayload('not json at all {{{'),
      throwsA(isA<BackupCorruptException>()),
    );
  });

  test('missing spendlyBackup marker throws BackupCorruptException', () async {
    expect(
      () => decodePayload(
        jsonEncode({'version': 1, 'encrypted': false, 'data': {}}),
      ),
      throwsA(isA<BackupCorruptException>()),
    );
  });

  test(
    'a v1-shaped file (no photo setting at all) still decodes correctly',
    () async {
      final v1Json = jsonEncode({
        'spendlyBackup': true,
        'version': 1,
        'encrypted': false,
        'data': _samplePayload().toJson(),
      });

      final decoded = await decodePayload(v1Json);
      expect(
        decoded.settings.any((s) => s.key == 'profile_photo_base64'),
        isFalse,
      );
      expect(decoded.categories.single.name, 'Food');
      expect(decoded.expenses.single.amountMinor, 24500);
    },
  );

  test(
    'a category with no "isIgnoredForBudget" key (pre-Sprint-12) defaults to false',
    () async {
      final catJson = _samplePayload().categories.single.toJson()
        ..remove('isIgnoredForBudget');
      final v1Json = jsonEncode({
        'spendlyBackup': true,
        'version': 1,
        'encrypted': false,
        'data': _samplePayload().toJson()..['categories'] = [catJson],
      });

      final decoded = await decodePayload(v1Json);
      expect(decoded.categories.single.isIgnoredForBudget, isFalse);
    },
  );

  test(
    'a backup with no "tags" key (pre-trip-feature) still decodes correctly',
    () async {
      final v1Json = jsonEncode({
        'spendlyBackup': true,
        'version': 1,
        'encrypted': false,
        'data': _samplePayload().toJson()..remove('tags'),
      });

      final decoded = await decodePayload(v1Json);
      expect(decoded.tags, isEmpty);
      // The expense's tagId (also absent pre-trip-feature) decodes to null.
      final v1JsonNoTagId = jsonEncode({
        'spendlyBackup': true,
        'version': 1,
        'encrypted': false,
        'data': _samplePayload().toJson()
          ..remove('tags')
          ..['expenses'] = [
            (_samplePayload().expenses.single.toJson()..remove('tagId')),
          ],
      });
      final decodedNoTagId = await decodePayload(v1JsonNoTagId);
      expect(decodedNoTagId.expenses.single.tagId, isNull);
    },
  );

  test(
    'a pre-v4 file (no fx keys) decodes as ordinary home-currency data',
    () async {
      final v3Json = jsonEncode({
        'spendlyBackup': true,
        'version': 3,
        'encrypted': false,
        'data': _samplePayload().toJson()
          ..['expenses'] = [
            _samplePayload().expenses.single.toJson()
              ..remove('fxCurrency')
              ..remove('fxAmountMinor'),
          ]
          ..['tags'] = [
            _samplePayload().tags.single.toJson()
              ..remove('fxCurrency')
              ..remove('fxRateMicros'),
          ],
      });

      final decoded = await decodePayload(v3Json);
      final expense = decoded.expenses.single;
      final tag = decoded.tags.single;

      // Absent fx keys mean "home currency" — the amount itself is untouched.
      expect(expense.amountMinor, 24500);
      expect(expense.fxCurrency, isNull);
      expect(expense.fxAmountMinor, isNull);
      expect(tag.fxCurrency, isNull);
      expect(tag.fxRateMicros, isNull);
    },
  );

  test('a v4 foreign expense round-trips both amounts', () async {
    final envelope = await encodeEnvelope(_samplePayload());
    final decoded = await decodePayload(envelope);

    final expense = decoded.expenses.single;
    expect(expense.amountMinor, 24500, reason: 'home currency, unchanged');
    expect(expense.fxCurrency, 'JPY');
    expect(expense.fxAmountMinor, 4500000);

    final tag = decoded.tags.single;
    expect(tag.fxCurrency, 'JPY');
    expect(tag.fxRateMicros, 550000);
  });

  test(
    'a pre-v5 file (no trip-date keys) decodes with no auto-tagging',
    () async {
      final v4Json = jsonEncode({
        'spendlyBackup': true,
        'version': 4,
        'encrypted': false,
        'data': _samplePayload().toJson()
          ..['tags'] = [
            _samplePayload().tags.single.toJson()
              ..remove('tripStartDate')
              ..remove('tripEndDate'),
          ],
      });

      final decoded = await decodePayload(v4Json);
      final tag = decoded.tags.single;
      expect(tag.tripStartDate, isNull);
      expect(tag.tripEndDate, isNull);
      // The fx pair from v4 is untouched by the missing v5 keys.
      expect(tag.fxCurrency, 'JPY');
    },
  );

  test('a v8 account round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        accounts: const [
          BackupAccount(
            id: 1,
            name: 'HDFC Bank',
            type: AccountType.bank,
            openingBalanceMinor: 500000,
            isArchived: false,
            externalId: 'acc-1',
            isDefault: true,
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).accounts.single;
    expect(decoded.name, 'HDFC Bank');
    expect(decoded.type, AccountType.bank);
    expect(decoded.openingBalanceMinor, 500000);
    expect(decoded.isArchived, isFalse);
    expect(decoded.externalId, 'acc-1');
    expect(decoded.isDefault, isTrue);
  });

  test('a pre-v13 account (no isDefault key) decodes as not default',
      () async {
    final v8Json = jsonEncode({
      'spendlyBackup': true,
      'version': 8,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['accounts'] = [
          {
            'id': 1,
            'name': 'Cash',
            'type': 'cash',
            'openingBalanceMinor': 0,
            'isArchived': false,
            'externalId': null,
            // No "isDefault" key at all.
          },
        ],
    });

    final decoded = (await decodePayload(v8Json)).accounts.single;
    expect(decoded.isDefault, isFalse);
  });

  test('an account opted out of net worth round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        accounts: const [
          BackupAccount(
            id: 1,
            name: 'Car loan',
            type: AccountType.bank,
            openingBalanceMinor: -1000000000,
            isArchived: false,
            externalId: 'acc-1',
            includeInNetWorth: false,
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).accounts.single;
    expect(decoded.includeInNetWorth, isFalse);
  });

  test('a pre-v18 account (no includeInNetWorth key) decodes as counted',
      () async {
    final v8Json = jsonEncode({
      'spendlyBackup': true,
      'version': 8,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['accounts'] = [
          {
            'id': 1,
            'name': 'Cash',
            'type': 'cash',
            'openingBalanceMinor': 0,
            'isArchived': false,
            'externalId': null,
            // No "includeInNetWorth" key at all.
          },
        ],
    });

    final decoded = (await decodePayload(v8Json)).accounts.single;
    expect(decoded.includeInNetWorth, isTrue);
  });

  test('a liability account round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        accounts: const [
          BackupAccount(
            id: 1,
            name: 'Car loan',
            type: AccountType.bank,
            openingBalanceMinor: -1000000000,
            isArchived: false,
            externalId: 'acc-1',
            isLiability: true,
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).accounts.single;
    expect(decoded.isLiability, isTrue);
    expect(decoded.openingBalanceMinor, -1000000000);
  });

  test('a pre-v19 account (no isLiability key) decodes as an asset',
      () async {
    final v8Json = jsonEncode({
      'spendlyBackup': true,
      'version': 8,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['accounts'] = [
          {
            'id': 1,
            'name': 'Cash',
            'type': 'cash',
            'openingBalanceMinor': 0,
            'isArchived': false,
            'externalId': null,
            // No "isLiability" key at all.
          },
        ],
    });

    final decoded = (await decodePayload(v8Json)).accounts.single;
    expect(decoded.isLiability, isFalse);
  });

  test('a frequently-used account round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        accounts: const [
          BackupAccount(
            id: 1,
            name: 'Cash',
            type: AccountType.cash,
            openingBalanceMinor: 0,
            isArchived: false,
            externalId: 'acc-1',
            isFrequent: true,
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).accounts.single;
    expect(decoded.isFrequent, isTrue);
  });

  test('a pre-v23 account (no isFrequent key) decodes as not frequent',
      () async {
    final v8Json = jsonEncode({
      'spendlyBackup': true,
      'version': 8,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['accounts'] = [
          {
            'id': 1,
            'name': 'Cash',
            'type': 'cash',
            'openingBalanceMinor': 0,
            'isArchived': false,
            'externalId': null,
            // No "isFrequent" key at all.
          },
        ],
    });

    final decoded = (await decodePayload(v8Json)).accounts.single;
    expect(decoded.isFrequent, isFalse);
  });

  test('a custom-type account round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        accounts: const [
          BackupAccount(
            id: 1,
            name: 'Car loan',
            type: AccountType.custom,
            openingBalanceMinor: -1000000000,
            isArchived: false,
            externalId: 'acc-1',
            customTypeName: 'Loan',
            customTypeIcon: '🏦',
            customTypeColorValue: 0xFF00FF00,
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).accounts.single;
    expect(decoded.type, AccountType.custom);
    expect(decoded.customTypeName, 'Loan');
    expect(decoded.customTypeIcon, '🏦');
    expect(decoded.customTypeColorValue, 0xFF00FF00);
  });

  test('a pre-v20 account (no custom-type keys) decodes with none set',
      () async {
    final v8Json = jsonEncode({
      'spendlyBackup': true,
      'version': 8,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['accounts'] = [
          {
            'id': 1,
            'name': 'Cash',
            'type': 'cash',
            'openingBalanceMinor': 0,
            'isArchived': false,
            'externalId': null,
            // No custom-type keys at all.
          },
        ],
    });

    final decoded = (await decodePayload(v8Json)).accounts.single;
    expect(decoded.customTypeName, isNull);
    expect(decoded.customTypeIcon, isNull);
    expect(decoded.customTypeColorValue, isNull);
  });

  test('a pre-v8 file (no accounts key) decodes with no accounts at all',
      () async {
    final v7Json = jsonEncode({
      'spendlyBackup': true,
      'version': 7,
      'encrypted': false,
      'data': _samplePayload().toJson()..remove('accounts'),
    });

    final decoded = await decodePayload(v7Json);
    expect(decoded.accounts, isEmpty);
  });

  test('a v9 ledger entry round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        ledgerEntries: [
          BackupLedgerEntry(
            id: 1,
            amountMinor: 5000000,
            date: DateTime(2026, 7, 1),
            accountId: 1,
            sourceLabel: 'Salary',
            note: 'July payout',
            externalId: 'inc-1',
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).ledgerEntries.single;
    expect(decoded.amountMinor, 5000000);
    expect(decoded.accountId, 1);
    expect(decoded.sourceLabel, 'Salary');
    expect(decoded.note, 'July payout');
    expect(decoded.externalId, 'inc-1');
    expect(decoded.kind, LedgerEntryKind.income);
    expect(decoded.counterAccountId, isNull);
  });

  test('a transfer ledger entry (schema v16) round-trips kind and '
      'counterAccountId', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        ledgerEntries: [
          BackupLedgerEntry(
            id: 1,
            amountMinor: 30000,
            date: DateTime(2026, 7, 15),
            accountId: 1,
            sourceLabel: null,
            note: 'Move to savings',
            externalId: 'xfer-1',
            kind: LedgerEntryKind.transfer,
            counterAccountId: 2,
          ),
        ],
      ),
    );
    final decoded = (await decodePayload(envelope)).ledgerEntries.single;
    expect(decoded.kind, LedgerEntryKind.transfer);
    expect(decoded.accountId, 1);
    expect(decoded.counterAccountId, 2);
  });

  test('a recurring income entry (schema v21) round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        ledgerEntries: [
          BackupLedgerEntry(
            id: 1,
            amountMinor: 5000000,
            date: DateTime(2026, 7, 1),
            accountId: 1,
            sourceLabel: 'Salary',
            note: null,
            externalId: 'inc-1',
            isRecurring: true,
            recurrence: Recurrence.monthly,
            nextDueDate: DateTime(2026, 8, 1),
            recurrenceEndDate: DateTime(2027, 7, 1),
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).ledgerEntries.single;
    expect(decoded.isRecurring, isTrue);
    expect(decoded.recurrence, Recurrence.monthly);
    expect(decoded.nextDueDate, DateTime(2026, 8, 1));
    expect(decoded.recurrenceEndDate, DateTime(2027, 7, 1));
  });

  test('a pre-v21 ledger entry (no recurrence keys) decodes as not '
      'recurring', () async {
    final v9Json = jsonEncode({
      'spendlyBackup': true,
      'version': 9,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['ledgerEntries'] = [
          {
            'id': 1,
            'amountMinor': 5000000,
            'date': DateTime(2026, 7, 1).toIso8601String(),
            'accountId': null,
            'sourceLabel': 'Salary',
            'note': null,
            'externalId': 'inc-1',
            // No recurrence keys at all.
          },
        ],
    });

    final decoded = (await decodePayload(v9Json)).ledgerEntries.single;
    expect(decoded.isRecurring, isFalse);
    expect(decoded.recurrence, isNull);
    expect(decoded.nextDueDate, isNull);
    expect(decoded.recurrenceEndDate, isNull);
  });

  test('a template-only ledger entry (schema v22) round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        ledgerEntries: [
          BackupLedgerEntry(
            id: 1,
            amountMinor: 5000000,
            date: DateTime(2026, 7, 1),
            accountId: 1,
            sourceLabel: 'Salary',
            note: null,
            externalId: 'inc-1',
            isRecurring: true,
            recurrence: Recurrence.monthly,
            nextDueDate: DateTime(2026, 8, 1),
            templateOnly: true,
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).ledgerEntries.single;
    expect(decoded.templateOnly, isTrue);
  });

  test('a pre-v22 ledger entry (no "templateOnly" key) decodes as false',
      () async {
    final v9Json = jsonEncode({
      'spendlyBackup': true,
      'version': 9,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['ledgerEntries'] = [
          {
            'id': 1,
            'amountMinor': 5000000,
            'date': DateTime(2026, 7, 1).toIso8601String(),
            'accountId': null,
            'sourceLabel': 'Salary',
            'note': null,
            'externalId': 'inc-1',
            // No "templateOnly" key at all.
          },
        ],
    });
    final decoded = (await decodePayload(v9Json)).ledgerEntries.single;
    expect(decoded.templateOnly, isFalse);
  });

  test('a pre-v16 ledger entry (no "kind" key) decodes as income', () async {
    final v9Json = jsonEncode({
      'spendlyBackup': true,
      'version': 9,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['ledgerEntries'] = [
          {
            'id': 1,
            'amountMinor': 50000,
            'date': DateTime(2026, 7, 1).toIso8601String(),
            'accountId': null,
            'sourceLabel': 'Salary',
            'note': null,
            'externalId': 'inc-1',
            // No "kind" or "counterAccountId" key at all.
          },
        ],
    });
    final decoded = (await decodePayload(v9Json)).ledgerEntries.single;
    expect(decoded.kind, LedgerEntryKind.income);
    expect(decoded.counterAccountId, isNull);
  });

  test('a pre-v9 file (no ledgerEntries key) decodes with no ledger entries '
      'at all', () async {
    final v8Json = jsonEncode({
      'spendlyBackup': true,
      'version': 8,
      'encrypted': false,
      'data': _samplePayload().toJson()..remove('ledgerEntries'),
    });

    final decoded = await decodePayload(v8Json);
    expect(decoded.ledgerEntries, isEmpty);
  });

  test('a v10 savings goal round-trips', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        savingsGoals: const [
          BackupGoal(
            id: 1,
            name: 'New laptop',
            targetMinor: 8000000,
            savedMinor: 2000000,
            isArchived: false,
            externalId: 'goal-1',
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).savingsGoals.single;
    expect(decoded.name, 'New laptop');
    expect(decoded.targetMinor, 8000000);
    expect(decoded.savedMinor, 2000000);
    expect(decoded.externalId, 'goal-1');
  });

  test('a pre-v10 file (no savingsGoals key) decodes with no goals at all',
      () async {
    final v9Json = jsonEncode({
      'spendlyBackup': true,
      'version': 9,
      'encrypted': false,
      'data': _samplePayload().toJson()..remove('savingsGoals'),
    });

    final decoded = await decodePayload(v9Json);
    expect(decoded.savingsGoals, isEmpty);
  });

  test('a v7 receipt round-trips as base64', () async {
    final payload = _samplePayload();
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: payload.expenses,
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
        receipts: [
          BackupReceipt(
            expenseId: payload.expenses.single.id,
            photoBase64: base64Encode([9, 8, 7]),
          ),
        ],
      ),
    );

    final decoded = (await decodePayload(envelope)).receipts.single;
    expect(decoded.expenseId, payload.expenses.single.id);
    expect(base64Decode(decoded.photoBase64), [9, 8, 7]);
  });

  test('a pre-v7 file (no receipts key) decodes with no receipts at all',
      () async {
    final v6Json = jsonEncode({
      'spendlyBackup': true,
      'version': 6,
      'encrypted': false,
      'data': _samplePayload().toJson()..remove('receipts'),
    });

    final decoded = await decodePayload(v6Json);
    expect(decoded.receipts, isEmpty);
  });

  test('a v6 recurring schedule round-trips', () async {
    final payload = _samplePayload();
    final scheduled = BackupExpense(
      id: payload.expenses.single.id,
      amountMinor: payload.expenses.single.amountMinor,
      categoryId: payload.expenses.single.categoryId,
      date: payload.expenses.single.date,
      note: payload.expenses.single.note,
      paymentMethod: payload.expenses.single.paymentMethod,
      isRecurring: true,
      recurrence: Recurrence.monthly,
      nextDueDate: DateTime(2026, 8, 1),
      recurrenceEndDate: DateTime(2027, 1, 1),
      tagId: payload.expenses.single.tagId,
      accountId: payload.expenses.single.accountId,
      createdAt: payload.expenses.single.createdAt,
      updatedAt: payload.expenses.single.updatedAt,
      externalId: payload.expenses.single.externalId,
      fxCurrency: payload.expenses.single.fxCurrency,
      fxAmountMinor: payload.expenses.single.fxAmountMinor,
    );
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: [scheduled],
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
      ),
    );

    final decoded = (await decodePayload(envelope)).expenses.single;
    // Without these two, a restore would keep the recurring flag but lose the
    // schedule — the reminder would never fire again.
    expect(decoded.isRecurring, isTrue);
    expect(decoded.recurrence, Recurrence.monthly);
    expect(decoded.nextDueDate, DateTime(2026, 8, 1));
    expect(decoded.recurrenceEndDate, DateTime(2027, 1, 1));
  });

  test('a pre-v6 file (no schedule keys) decodes as nothing scheduled', () async {
    final v5Json = jsonEncode({
      'spendlyBackup': true,
      'version': 5,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['expenses'] = [
          _samplePayload().expenses.single.toJson()
            ..remove('nextDueDate')
            ..remove('recurrenceEndDate'),
        ],
    });

    final decoded = (await decodePayload(v5Json)).expenses.single;
    expect(decoded.nextDueDate, isNull);
    expect(decoded.recurrenceEndDate, isNull);
    // The v4 fx pair is untouched by the missing v6 keys.
    expect(decoded.fxCurrency, 'JPY');
  });

  test('a template-only expense (schema v22) round-trips', () async {
    final payload = _samplePayload();
    final template = BackupExpense(
      id: payload.expenses.single.id,
      amountMinor: payload.expenses.single.amountMinor,
      categoryId: payload.expenses.single.categoryId,
      date: payload.expenses.single.date,
      note: payload.expenses.single.note,
      paymentMethod: payload.expenses.single.paymentMethod,
      isRecurring: true,
      recurrence: Recurrence.monthly,
      nextDueDate: DateTime(2026, 8, 1),
      recurrenceEndDate: null,
      tagId: payload.expenses.single.tagId,
      accountId: payload.expenses.single.accountId,
      createdAt: payload.expenses.single.createdAt,
      updatedAt: payload.expenses.single.updatedAt,
      externalId: payload.expenses.single.externalId,
      fxCurrency: payload.expenses.single.fxCurrency,
      fxAmountMinor: payload.expenses.single.fxAmountMinor,
      templateOnly: true,
    );
    final envelope = await encodeEnvelope(
      BackupPayload(
        exportedAt: payload.exportedAt,
        categories: payload.categories,
        expenses: [template],
        budgets: payload.budgets,
        tags: payload.tags,
        settings: payload.settings,
      ),
    );

    final decoded = (await decodePayload(envelope)).expenses.single;
    expect(decoded.templateOnly, isTrue);
  });

  test('a pre-v22 file (no "templateOnly" key) decodes as false', () async {
    final v5Json = jsonEncode({
      'spendlyBackup': true,
      'version': 5,
      'encrypted': false,
      'data': _samplePayload().toJson()
        ..['expenses'] = [
          _samplePayload().expenses.single.toJson()..remove('templateOnly'),
        ],
    });

    final decoded = (await decodePayload(v5Json)).expenses.single;
    expect(decoded.templateOnly, isFalse);
  });

  test(
    'a real expense and its cloned recurring template have distinct '
    'Merge fingerprints despite matching amount/date/category/note',
    () {
      const shared = (
        amountMinor: 19900,
        categoryId: 3,
        note: 'Netflix',
        paymentMethod: 'UPI',
      );
      final date = DateTime(2026, 3, 3);
      final real = BackupExpense(
        id: 1,
        amountMinor: shared.amountMinor,
        categoryId: shared.categoryId,
        date: date,
        note: shared.note,
        paymentMethod: shared.paymentMethod,
        isRecurring: false,
        recurrence: null,
        tagId: null,
        accountId: null,
        createdAt: date,
        updatedAt: date,
        externalId: 'real-1',
        fxCurrency: null,
        fxAmountMinor: null,
        nextDueDate: null,
        recurrenceEndDate: null,
      );
      final template = BackupExpense(
        id: 2,
        amountMinor: shared.amountMinor,
        categoryId: shared.categoryId,
        date: date,
        note: shared.note,
        paymentMethod: shared.paymentMethod,
        isRecurring: true,
        recurrence: Recurrence.monthly,
        tagId: null,
        accountId: null,
        createdAt: date,
        updatedAt: date,
        externalId: 'template-1',
        fxCurrency: null,
        fxAmountMinor: null,
        nextDueDate: DateTime(2026, 4, 3),
        recurrenceEndDate: null,
        templateOnly: true,
      );

      expect(
        real.fingerprint(mappedCategoryId: shared.categoryId),
        isNot(template.fingerprint(mappedCategoryId: shared.categoryId)),
      );
    },
  );

  test('a v5 trip date range round-trips', () async {
    final envelope = await encodeEnvelope(_samplePayload());
    final decoded = await decodePayload(envelope);

    final tag = decoded.tags.single;
    expect(tag.tripStartDate, DateTime(2026, 7, 1));
    expect(tag.tripEndDate, DateTime(2026, 7, 10));
  });

  test('the photo travels as an ordinary settings row and round-trips', () async {
    final payload = BackupPayload(
      exportedAt: DateTime(2026, 7, 23, 10, 15),
      categories: const [],
      expenses: const [],
      budgets: const [],
      settings: [
        BackupSetting(
          key: 'profile_photo_base64',
          value: base64Encode(utf8.encode('fake jpeg bytes')),
        ),
      ],
      tags: const [],
    );
    final envelope = await encodeEnvelope(payload);
    final decoded = await decodePayload(envelope);
    expect(jsonEncode(decoded.toJson()), jsonEncode(payload.toJson()));
  });

  test(
    'a legacy v2 file with a top-level profilePhotoBase64 field folds it into settings',
    () async {
      final legacyJson = jsonEncode({
        'spendlyBackup': true,
        'version': 2,
        'encrypted': false,
        'data': _samplePayload().toJson()
          ..['profilePhotoBase64'] = base64Encode(
            utf8.encode('fake jpeg bytes'),
          ),
      });

      final decoded = await decodePayload(legacyJson);
      final photoSetting = decoded.settings.singleWhere(
        (s) => s.key == 'profile_photo_base64',
      );
      expect(photoSetting.value, base64Encode(utf8.encode('fake jpeg bytes')));
    },
  );

  test('future version is rejected before a password would ever be needed', () {
    final future = jsonEncode({
      'spendlyBackup': true,
      'version': 99,
      'encrypted': true,
    });
    expect(
      () => peekEnvelope(future),
      throwsA(isA<BackupVersionTooNewException>()),
    );
    expect(
      () => decodePayload(future),
      throwsA(isA<BackupVersionTooNewException>()),
    );
  });
}

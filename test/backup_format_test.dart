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
      tagId: 1,
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

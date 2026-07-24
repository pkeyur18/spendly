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
      createdAt: DateTime(2026, 7, 1, 9, 3),
      updatedAt: DateTime(2026, 7, 1, 9, 3),
    ),
  ],
  budgets: const [
    BackupBudget(
      id: 1,
      categoryId: null,
      amountMinor: 5000000,
      period: BudgetPeriod.monthly,
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
    'a v1-shaped file (no profilePhotoBase64) still decodes correctly',
    () async {
      // Hand-written, shaped exactly like a pre-Sprint-10 export — the
      // payload has no "profilePhotoBase64" key at all.
      final v1Json = jsonEncode({
        'spendlyBackup': true,
        'version': 1,
        'encrypted': false,
        'data': _samplePayload().toJson()..remove('profilePhotoBase64'),
      });

      final decoded = await decodePayload(v1Json);
      expect(decoded.profilePhotoBase64, isNull);
      expect(decoded.categories.single.name, 'Food');
      expect(decoded.expenses.single.amountMinor, 24500);
    },
  );

  test('a v2 payload round-trips its profilePhotoBase64 field', () async {
    final payload = BackupPayload(
      exportedAt: DateTime(2026, 7, 23, 10, 15),
      categories: const [],
      expenses: const [],
      budgets: const [],
      settings: const [],
      profilePhotoBase64: base64Encode(utf8.encode('fake jpeg bytes')),
    );
    final envelope = await encodeEnvelope(payload);
    final decoded = await decodePayload(envelope);
    expect(decoded.profilePhotoBase64, payload.profilePhotoBase64);
  });

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

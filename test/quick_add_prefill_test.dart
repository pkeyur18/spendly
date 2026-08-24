import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/expenses/quick_add_screen.dart';

/// Covers the edit-vs-"add again" split at Quick Add's entry point. The two
/// modes prefill identically, so the only things separating them are which
/// date the form opens on and — critically — which source field is set, since
/// `_isEdit` reads `editing` alone and decides whether _save updates the
/// original row or inserts a new one.
void main() {
  final march10 = DateTime(2026, 3, 10, 14, 30);
  final now = DateTime(2026, 6, 15, 9);

  ExpenseRow expense() => ExpenseRow(
    id: 7,
    amountMinor: 2435,
    categoryId: 3,
    date: march10,
    note: 'lunch',
    paymentMethod: 'UPI',
    isRecurring: false,
    recurrence: null,
    tagId: 2,
    fxCurrency: null,
    fxAmountMinor: null,
    createdAt: march10,
    updatedAt: march10,
    externalId: 'abc',
  );

  test('a fresh add has no source and opens on today', () {
    final p = quickAddPrefill(editing: null, duplicateOf: null, now: now);
    expect(p.source, isNull);
    expect(p.date, now);
  });

  test('an edit prefills from the row and keeps its original date', () {
    final e = expense();
    final p = quickAddPrefill(editing: e, duplicateOf: null, now: now);
    expect(p.source, e);
    expect(p.date, march10);
  });

  test('a copy prefills from the row but opens on today', () {
    final e = expense();
    final p = quickAddPrefill(editing: null, duplicateOf: e, now: now);
    // Same prefill source — the copy inherits amount, category, note, trip.
    expect(p.source, e);
    // ...but not the date. Dating it to the original would also drag a stale
    // trip along via auto-tagging.
    expect(p.date, now);
  });

  test('editing wins if both are somehow supplied, so a copy can never '
      'overwrite the row it copied', () {
    final editing = expense();
    final other = expense();
    final p = quickAddPrefill(
      editing: editing,
      duplicateOf: other,
      now: now,
    );
    expect(p.source, same(editing));
    expect(p.date, march10);
  });
}

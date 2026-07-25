import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/reports/report_model.dart';
import 'package:spendly/features/reports/report_providers.dart';

/// Deleting a transaction from the custom report screen's new list must flow
/// back through the same live stream reportProvider watches — no manual
/// invalidation. Provider-level test (Drift streams never settle in a widget
/// pump, per project convention).
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final range = (DateTime(2026, 7, 1), DateTime(2026, 8, 1));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    container.listen(reportProvider(range), (_, _) {});
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('deleting an expense updates the report reactively', () async {
    final repo = container.read(expenseRepositoryProvider);
    final id1 = await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 7, 10),
    );
    await repo.add(
      amount: Money.parse('50'),
      categoryId: 2,
      date: DateTime(2026, 7, 12),
    );

    await _waitUntilReport(container, range, (d) => d.txnCount == 2);
    expect(
      container.read(reportProvider(range)).value!.total,
      Money.fromMinor(15000),
    );

    await repo.delete(id1);

    await _waitUntilReport(container, range, (d) => d.txnCount == 1);
    final data = container.read(reportProvider(range)).value!;
    expect(data.total, Money.fromMinor(5000));
    expect(data.expenses.single.categoryId, 2);
  });
}

/// Waits until [range]'s report satisfies [test], or fails after 5s.
Future<void> _waitUntilReport(
  ProviderContainer container,
  DateRange range,
  bool Function(ReportData) test,
) async {
  final completer = Completer<void>();
  final sub = container.listen(reportProvider(range), (_, next) {
    final value = next.value;
    if (value != null && test(value) && !completer.isCompleted) {
      completer.complete();
    }
  }, fireImmediately: true);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

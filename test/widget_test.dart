import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/home/dashboard_providers.dart';

/// Dashboard reactive-wiring tests at the provider level (no widget pump —
/// live Drift streams + fl_chart never settle, which hangs pumpAndSettle).
/// This is the exit-criterion wiring: adding an expense updates the dashboard.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    // Keep the stream providers alive for the test's duration.
    container.listen(currentMonthExpensesProvider, (_, _) {});
    container.listen(allCategoriesProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<void> primeStreams() async {
    await container.read(allCategoriesProvider.future);
    await container.read(currentMonthExpensesProvider.future);
  }

  test('empty state: zero total, no budget, 8 seeded categories', () async {
    await primeStreams();
    expect(container.read(monthTotalProvider), Money.zero);
    expect(container.read(categoryBreakdownProvider), isEmpty);
    expect(container.read(categoriesByIdProvider).length, 8);
    expect(container.read(overallBudgetProvider).value, isNull);
  });

  test('adding an expense updates monthTotal + breakdown reactively', () async {
    await primeStreams();
    final repo = container.read(expenseRepositoryProvider);

    await repo.add(amount: Money.parse('100'), categoryId: 1);
    await _waitUntil(
        container, monthTotalProvider, (m) => m == Money.fromMinor(10000));

    await repo.add(amount: Money.parse('50.50'), categoryId: 2);
    await _waitUntil(
        container, monthTotalProvider, (m) => m == Money.fromMinor(15050));

    final breakdown = container.read(categoryBreakdownProvider);
    expect(breakdown.length, 2);
    expect(breakdown.first.$2, Money.fromMinor(10000)); // cat1 largest, sorted desc
  });

  test('lastUsedCategoryId tracks the most recent expense', () async {
    await primeStreams();
    final repo = container.read(expenseRepositoryProvider);

    expect(container.read(lastUsedCategoryIdProvider), isNull);
    await repo.add(amount: Money.parse('10'), categoryId: 3);
    await _waitUntil(
        container, lastUsedCategoryIdProvider, (id) => id == 3);
  });
}

/// Waits until [provider]'s value satisfies [test], or fails after 5s.
Future<void> _waitUntil<T>(
  ProviderContainer container,
  Provider<T> provider,
  bool Function(T) test,
) async {
  final done = Completer<void>();
  final sub = container.listen<T>(provider, (_, next) {
    if (!done.isCompleted && test(next)) done.complete();
  }, fireImmediately: true);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

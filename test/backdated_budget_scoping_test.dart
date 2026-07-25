import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

/// Guards the fix for a backdated Quick Add entry: the budget-threshold
/// check must compare against the *expense's* month, not "now". Provider
/// level only (no widget pump — see widget_test.dart's Drift-stream note).
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final march = DateTime(2026, 3, 1);
  final april = DateTime(2026, 4, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test(
    'an expense backdated into March is scoped to March\'s budget, not the current month\'s',
    () async {
      final budgets = container.read(budgetRepositoryProvider);
      final expenses = container.read(expenseRepositoryProvider);
      await budgets.setForCategory(march, 1, Money.parse('100'));
      await budgets.setForCategory(april, 1, Money.parse('9999'));

      // Backdated into March even though "today" is in April.
      await expenses.add(
        amount: Money.parse('90'),
        categoryId: 1,
        date: DateTime(2026, 3, 15),
      );

      final marchKey = monthKeyFor(march);
      // Keep the stream provider alive past its first read (it auto-disposes
      // otherwise, before .family's Provider.read can see its data).
      container.listen(allBudgetsForMonthProvider(marchKey), (_, _) {});
      await container.read(allBudgetsForMonthProvider(marchKey).future);

      final (start, end) = monthBounds(march);
      final marchTotals = await expenses.totalsByCategory(start, end);
      final marchBudget =
          container.read(perCategoryBudgetsForMonthProvider(marchKey))[1];
      expect(marchTotals[1], Money.parse('90'));
      expect(marchBudget, Money.parse('100'));
      // 90% of March's 100 budget crosses 80% — this is what the alert
      // check must see; April's unrelated 9999 budget must not be used.
      expect(
        crossedThresholds(Money.zero, marchTotals[1]!, marchBudget!),
        [80],
      );
    },
  );
}

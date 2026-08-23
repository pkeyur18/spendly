import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/features/budgets/budget_nudge_provider.dart';

void main() {
  group('shouldShowBudgetNudge (pure predicate)', () {
    test('false outside the last 3 days of the month', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 20),
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: null,
        ),
        isFalse,
      );
    });

    test('false when next month budget is already set', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 30),
          nextMonthBudgetSet: true,
          lastNudgedMonthKey: null,
        ),
        isFalse,
      );
    });

    test('false when already nudged this month', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 30),
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: '2026-08',
        ),
        isFalse,
      );
    });

    test('true in the last 3 days, unset, not yet nudged', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 30), // August has 31 days
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: '2026-07',
        ),
        isTrue,
      );
    });

    test('handles short months correctly (Feb 26/27/28)', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 2, 26), // Feb 2026 has 28 days
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: null,
        ),
        isTrue,
      );
    });
  });

  group('budgetNudgeCheckProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
    });
    tearDown(() {
      container.dispose();
      db.close();
    });

    test('does not mark the gate outside the nudge window', () async {
      await container.read(budgetNudgeCheckProvider.future);
      final settings = container.read(settingsRepositoryProvider);
      expect(
        await settings.get(SettingsRepository.lastBudgetNudgeMonthKey),
        isNull,
      );
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/recap/recap_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  final now = DateTime.now();
  final currentKey = monthKeyFor(now);
  final prevMonth = DateTime(now.year, now.month - 1, 1);

  test('no expenses last month -> gate stays unmarked (skips fresh installs)', () async {
    await container.read(monthlyRecapCheckProvider.future);
    final settings = container.read(settingsRepositoryProvider);
    expect(
      await settings.get(SettingsRepository.lastRecapMonthKey),
      isNull,
    );
  });

  test('an expense exists last month -> marks the gate for the current month', () async {
    await ExpenseRepository(db).add(
      amount: Money.parse('500'),
      categoryId: 1,
      date: prevMonth,
    );

    await container.read(monthlyRecapCheckProvider.future);
    final settings = container.read(settingsRepositoryProvider);
    expect(
      await settings.get(SettingsRepository.lastRecapMonthKey),
      currentKey,
    );
  });

  test('already marked for the current month -> stays marked, no crash on rerun', () async {
    await ExpenseRepository(db).add(
      amount: Money.parse('500'),
      categoryId: 1,
      date: prevMonth,
    );
    final settings = container.read(settingsRepositoryProvider);
    await settings.set(SettingsRepository.lastRecapMonthKey, currentKey);

    await container.read(monthlyRecapCheckProvider.future);
    expect(
      await settings.get(SettingsRepository.lastRecapMonthKey),
      currentKey,
    );
  });
}

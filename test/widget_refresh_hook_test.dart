import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/widgets/widget_refresh.dart';
import 'package:spendly/features/widgets/widget_snapshot.dart';

/// Verifies the on-write hook (docs/known-issues.md push-back #3): a DB
/// write reaches the widget snapshot with no explicit refreshWidgets() call
/// at the write site, driven only by arming widgetRefreshHookProvider once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  final savedData = <String, String>{};

  setUp(() {
    savedData.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (
          call,
        ) async {
          if (call.method == 'saveWidgetData') {
            final args = call.arguments as Map;
            savedData[args['id'] as String] = args['data'] as String;
          }
          return null;
        });

    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    container.dispose();
    return db.close();
  });

  test('a write reaches the widget snapshot with no explicit refresh call', () async {
    container.read(widgetRefreshHookProvider); // arm the hook, as app.dart does

    await container
        .read(expenseRepositoryProvider)
        .add(amount: Money.parse('250'), categoryId: 1, date: DateTime.now());

    await _waitUntil(() => savedData.containsKey(WidgetKeys.todayTotal));
    expect(savedData[WidgetKeys.todayTotal], contains('250'));
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

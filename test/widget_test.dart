import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/app.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';

void main() {
  testWidgets('renders empty home state', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SpendlyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spendly'), findsOneWidget);
    expect(find.text('No expenses yet'), findsOneWidget);
  });
}

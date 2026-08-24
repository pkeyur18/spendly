import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/theme/app_theme.dart';
import 'package:spendly/core/widgets/glass.dart';

void main() {
  testWidgets('showGlassSheet renders a glass surface with a transparent barrier', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showGlassSheet<void>(
                  context,
                  builder: (_) => const SizedBox(
                    height: 100,
                    child: Text('sheet content'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sheet content'), findsOneWidget);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/theme/app_theme.dart';
import 'package:spendly/core/theme/tokens.dart';
import 'package:spendly/core/widgets/app_card.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, ThemeData theme) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: AppCard(child: Text('hello'))),
      ),
    );
  }

  Container decoratedContainer(WidgetTester tester) => tester.widget<Container>(
    find.descendant(
      of: find.byType(BackdropFilter),
      matching: find.byType(Container),
    ),
  );

  testWidgets('renders a blurred glass surface in light theme', (
    tester,
  ) async {
    await pumpCard(tester, AppTheme.light());

    expect(find.byType(BackdropFilter), findsOneWidget);
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, isA<ImageFilter>());

    final decoration = decoratedContainer(tester).decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.light.glassCard);
    expect(decoration.border, Border.all(color: AppPalette.light.glassBorder));
  });

  testWidgets('renders a blurred glass surface in dark theme', (
    tester,
  ) async {
    await pumpCard(tester, AppTheme.dark());

    final decoration = decoratedContainer(tester).decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.dark.glassCard);
    expect(decoration.border, Border.all(color: AppPalette.dark.glassBorder));
  });

  testWidgets('tap still works through the glass wrapper', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppCard(onTap: () => tapped = true, child: const Text('x')),
        ),
      ),
    );

    await tester.tap(find.byType(AppCard));
    expect(tapped, isTrue);
  });
}

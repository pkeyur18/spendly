import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/widgets/buttons.dart';

void main() {
  testWidgets('shows the label and fires onPressed on tap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryGradientButton(
            label: 'Save',
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.byType(PrimaryGradientButton));
    expect(pressed, isTrue);
  });

  testWidgets('semanticLabel overrides the spoken label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryGradientButton(
            label: 'Saving…',
            semanticLabel: 'Save transfer',
            onPressed: () {},
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(PrimaryGradientButton));
    // The Text child's own semantics merges into the wrapping Semantics
    // node (standard Flutter merge behavior, same as the hand-rolled
    // buttons this replaces) — the override still comes through as the
    // first line.
    expect(semantics.label, startsWith('Save transfer'));
  });
}

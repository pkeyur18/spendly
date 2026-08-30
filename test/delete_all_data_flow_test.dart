import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/profile/delete_all_data_flow.dart';

/// ResetConfirmDialog's type-to-confirm gate (FR-58) had zero coverage —
/// nothing verified the destructive "Delete all data" action actually stays
/// unreachable until the exact confirmation word is typed. No live Drift
/// stream involved (ADR-009's exception case), so a plain widget pump is
/// safe here, same style as `app_card_test.dart`/`buttons_test.dart`.
void main() {
  Finder deleteButton() => find.widgetWithText(FilledButton, 'Delete all data');

  // showDialog's Future only resolves once the dialog is popped, so its
  // eventual value is captured on this mutable holder rather than returned
  // directly — a test can open the dialog, interact with it further, then
  // read the holder once the resulting pop has actually happened.
  Future<_DialogResult> openDialog(WidgetTester tester) async {
    final holder = _DialogResult();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                holder.value = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ResetConfirmDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return holder;
  }

  testWidgets('the delete button starts disabled', (tester) async {
    await openDialog(tester);
    expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNull);
  });

  testWidgets('typing the exact confirm word enables the delete button',
      (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();

    expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNotNull);
  });

  testWidgets(
    'a partial or mismatched confirmation leaves the button disabled',
    (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELET');
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE ');
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNull);
    },
  );

  testWidgets('tapping the enabled delete button resolves the dialog true',
      (tester) async {
    final holder = await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(holder.value, isTrue);
  });

  testWidgets('cancel resolves the dialog false without requiring any text',
      (tester) async {
    final holder = await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(holder.value, isFalse);
  });
}

class _DialogResult {
  bool? value;
}

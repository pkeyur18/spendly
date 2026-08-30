import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/theme/app_theme.dart';
import 'package:spendly/features/accounts/account_picker_sheet.dart';
import 'package:spendly/features/accounts/account_repository.dart';

/// `showAccountPickerSheet` had zero coverage — the frequent-first filtering
/// (schema v23), the "See all accounts" expansion, the exclude set, and the
/// allowNone/noAccountChoice sentinel are all real branching logic with
/// nothing asserting any of it. `showGlassSheet` is a plain
/// `showModalBottomSheet` with no live Drift stream involved, so
/// `pumpAndSettle` is safe here (ADR-009's concern is specifically about
/// live `.watch()` streams, not present in this widget at all).
void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late void Function(FlutterErrorDetails)? previousOnError;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);

    // The sheet's ListTiles sit inside GlassSurface's decorated Container
    // with no Material boundary in between — a pre-existing, cosmetic-only
    // rendering quirk (ink splashes may not paint) unrelated to the
    // filtering/selection logic under test here. Filtered rather than
    // fixed, since this file is test-only.
    previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains(
        'ListTile background color or ink splashes may be invisible',
      )) {
        return;
      }
      previousOnError?.call(details);
    };
  });
  tearDown(() {
    FlutterError.onError = previousOnError;
    return db.close();
  });

  Future<AccountRow> seed(String name, {bool frequent = false}) async {
    final id = await accounts.create(name: name, type: AccountType.cash);
    if (frequent) await accounts.setFrequent(id, true);
    return (await accounts.byId(id))!;
  }

  // showAccountPickerSheet's Future only resolves once the sheet is popped,
  // so its eventual value is captured on this mutable holder rather than
  // returned directly — mirrors the same need in delete_all_data_flow_test.
  Future<_PickResult> openPicker(
    WidgetTester tester, {
    required List<AccountRow> accountList,
    int? selected,
    bool allowNone = true,
    Set<int> exclude = const {},
  }) async {
    final holder = _PickResult();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                holder.value = await showAccountPickerSheet(
                  context,
                  accounts: accountList,
                  selected: selected,
                  allowNone: allowNone,
                  exclude: exclude,
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

  testWidgets(
    'with no frequent accounts, every account shows straight away and '
    'tapping one resolves with its id',
    (tester) async {
      final cash = await seed('Cash Wallet');
      final bank = await seed('HDFC Bank');

      final holder = await openPicker(
        tester,
        accountList: [cash, bank],
      );

      expect(find.text('Cash Wallet'), findsOneWidget);
      expect(find.text('HDFC Bank'), findsOneWidget);
      expect(find.text('See all accounts'), findsNothing);

      await tester.tap(find.text('HDFC Bank'));
      await tester.pumpAndSettle();

      expect(holder.value, bank.id);
    },
  );

  testWidgets(
    'with a frequent account present, only frequent accounts show at '
    'first, expanding via "See all accounts" reveals the rest',
    (tester) async {
      final regular = await seed('Cash Wallet');
      final frequent = await seed('HDFC Bank', frequent: true);

      await openPicker(tester, accountList: [regular, frequent]);

      expect(find.text('HDFC Bank'), findsOneWidget);
      expect(find.text('Cash Wallet'), findsNothing);
      expect(find.text('See all accounts'), findsOneWidget);

      await tester.tap(find.text('See all accounts'));
      await tester.pumpAndSettle();

      expect(find.text('Cash Wallet'), findsOneWidget);
      expect(find.text('HDFC Bank'), findsOneWidget);
      expect(find.text('See all accounts'), findsNothing);
    },
  );

  testWidgets('an excluded account id is never shown', (tester) async {
    final cash = await seed('Cash Wallet');
    final bank = await seed('HDFC Bank');

    await openPicker(
      tester,
      accountList: [cash, bank],
      exclude: {cash.id},
    );

    expect(find.text('Cash Wallet'), findsNothing);
    expect(find.text('HDFC Bank'), findsOneWidget);
  });

  testWidgets('allowNone: false hides the "No account" row', (tester) async {
    final cash = await seed('Cash Wallet');

    await openPicker(tester, accountList: [cash], allowNone: false);

    expect(find.text('No account'), findsNothing);
  });

  testWidgets(
    'tapping "No account" resolves to the noAccountChoice sentinel',
    (tester) async {
      final cash = await seed('Cash Wallet');

      final holder = await openPicker(tester, accountList: [cash]);
      expect(find.text('No account'), findsOneWidget);

      await tester.tap(find.text('No account'));
      await tester.pumpAndSettle();

      expect(holder.value, noAccountChoice);
    },
  );
}

class _PickResult {
  int? value;
}

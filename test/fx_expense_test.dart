import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/fx.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/tags/tag_repository.dart';

/// Storage-layer guarantees for foreign-currency trip spending.
///
/// The rule everything else depends on: `amountMinor` is ALWAYS home
/// currency, so no aggregate needs to know currencies exist.
void main() {
  late AppDatabase db;
  late ExpenseRepository expenses;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenses = ExpenseRepository(db);
    tags = TagRepository(db);
  });
  tearDown(() => db.close());

  /// Logs an expense the way QuickAddScreen does: convert at the trip's rate,
  /// store home currency plus the foreign receipt.
  Future<int> logAbroad(TagRow trip, String typed, {DateTime? date}) {
    final fx = Money.parse(typed);
    return expenses.add(
      amount: Money.fromMinor(
        convertToHomeMinor(fx.minor, trip.fxRateMicros!),
      ),
      categoryId: 1,
      date: date ?? DateTime(2026, 3, 10),
      tagId: trip.id,
      fxCurrency: trip.fxCurrency,
      fxAmount: fx,
    );
  }

  Future<TagRow> createTrip({int rateMicros = 2620000}) async {
    final id = await tags.create(
      name: 'Thailand',
      colorValue: 0xFFF59E0B,
      fxCurrency: 'THB',
      fxRateMicros: rateMicros,
    );
    return (await tags.byId(id))!;
  }

  test('a trip tag round-trips its currency and rate', () async {
    final trip = await createTrip();
    expect(trip.fxCurrency, 'THB');
    expect(trip.fxRateMicros, 2620000);
    expect(trip.isTravel, isTrue);
  });

  test('an ordinary tag is not a trip abroad', () async {
    final id = await tags.create(name: 'Groceries', colorValue: 0xFF6366F1);
    final tag = (await tags.byId(id))!;
    expect(tag.fxCurrency, isNull);
    expect(tag.isTravel, isFalse);
  });

  test('stores home currency in amountMinor and the receipt alongside', () async {
    final trip = await createTrip();
    final id = await logAbroad(trip, '450'); // ฿450 at 2.62

    final row = (await expenses.watchMonth(
      DateTime(2026, 3, 1),
    ).first).firstWhere((e) => e.id == id);

    expect(row.amount, Money.fromMinor(117900)); // ₹1,179.00
    expect(row.fxAmount, Money.fromMinor(45000)); // ฿450.00
    expect(row.fxCurrency, 'THB');
    expect(row.isForeign, isTrue);
  });

  test('aggregates count the home amount without knowing about currencies', () async {
    final trip = await createTrip();
    await logAbroad(trip, '450'); // -> ₹1,179.00
    await expenses.add(
      amount: Money.parse('340.00'), // an ordinary domestic expense
      categoryId: 1,
      date: DateTime(2026, 3, 11),
    );

    // monthTotal and totalsByCategory have no fx awareness at all — they
    // must still land on the converted rupee figures.
    expect(
      await expenses.monthTotal(DateTime(2026, 3, 1)),
      Money.fromMinor(117900 + 34000),
    );
    final byCategory = await expenses.totalsByCategory(
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
    );
    expect(byCategory[1], Money.fromMinor(151900));
  });

  test('a domestic expense stores no foreign receipt', () async {
    final id = await expenses.add(
      amount: Money.parse('340.00'),
      categoryId: 1,
      date: DateTime(2026, 3, 11),
    );
    final row = (await expenses.watchMonth(
      DateTime(2026, 3, 1),
    ).first).firstWhere((e) => e.id == id);
    expect(row.fxCurrency, isNull);
    expect(row.fxAmountMinor, isNull);
    expect(row.isForeign, isFalse);
  });

  group('the freeze rule', () {
    test('editing the trip rate never rewrites what is already saved', () async {
      final trip = await createTrip();
      final id = await logAbroad(trip, '450');

      await tags.setFxRate(trip.id, 2900000); // rate moved to 2.90

      final row = (await expenses.watchMonth(
        DateTime(2026, 3, 1),
      ).first).firstWhere((e) => e.id == id);
      expect(row.amount, Money.fromMinor(117900), reason: 'frozen at 2.62');
      expect(await expenses.monthTotal(DateTime(2026, 3, 1)),
          Money.fromMinor(117900),
          reason: 'a past month total must not move when a rate changes');
    });

    test('a new expense after the edit uses the new rate', () async {
      final trip = await createTrip();
      await logAbroad(trip, '450'); // ₹1,179.00 at 2.62

      await tags.setFxRate(trip.id, 2900000);
      final updated = (await tags.byId(trip.id))!;
      final id = await logAbroad(updated, '450', date: DateTime(2026, 3, 12));

      final row = (await expenses.watchMonth(
        DateTime(2026, 3, 1),
      ).first).firstWhere((e) => e.id == id);
      expect(row.amount, Money.fromMinor(130500)); // ₹1,305.00 at 2.90

      // Both rates coexist in one trip; the report's average blends them.
      expect(
        averageRateMicros(117900 + 130500, 45000 + 45000),
        2760000, // 2.76
      );
    });
  });

  test('moving an expense off a trip clears the foreign receipt', () async {
    final trip = await createTrip();
    final id = await logAbroad(trip, '450');

    // What QuickAddScreen writes when the trip chip is cleared: a home
    // amount, and both fx fields explicitly nulled rather than left stale.
    await expenses.update(
      id,
      amount: Money.parse('1179.00'),
      tagId: const Value(null),
      fxCurrency: const Value(null),
      fxAmount: const Value(null),
    );

    final row = (await expenses.watchMonth(
      DateTime(2026, 3, 1),
    ).first).firstWhere((e) => e.id == id);
    expect(row.tagId, isNull);
    expect(row.fxCurrency, isNull);
    expect(row.fxAmountMinor, isNull);
    expect(row.isForeign, isFalse);
  });

  test('hasExpenses gates changing a trip currency', () async {
    final trip = await createTrip();
    expect(await tags.hasExpenses(trip.id), isFalse);

    await logAbroad(trip, '450');
    expect(await tags.hasExpenses(trip.id), isTrue);
  });

  test('deleting a trip untags its expenses but keeps the home amount', () async {
    final trip = await createTrip();
    final id = await logAbroad(trip, '450');

    await tags.delete(trip.id);

    final row = (await expenses.watchMonth(
      DateTime(2026, 3, 1),
    ).first).firstWhere((e) => e.id == id);
    expect(row.tagId, isNull);
    expect(row.amount, Money.fromMinor(117900), reason: 'spend is not lost');
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  test('add then read back exact amount (no float drift)', () async {
    final id = await repo.add(
      amount: Money.parse('24.35'),
      categoryId: 1,
      date: DateTime(2026, 3, 10),
    );
    final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    final row = rows.firstWhere((e) => e.id == id);
    expect(row.amount, Money.fromMinor(2435));
  });

  test('monthTotal sums minor units exactly', () async {
    await repo.add(
      amount: Money.parse('100.00'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
    );
    await repo.add(
      amount: Money.parse('250.50'),
      categoryId: 1,
      date: DateTime(2026, 3, 20),
    );
    final total = await repo.monthTotal(DateTime(2026, 3, 15));
    expect(total, Money.fromMinor(35050)); // 350.50
  });

  test('monthTotal excludes other months', () async {
    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 31, 23, 59),
    );
    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 4, 1, 0, 0),
    );
    expect(await repo.monthTotal(DateTime(2026, 3, 1)), Money.fromMinor(10000));
  });

  test('totalsByCategory groups correctly', () async {
    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 5),
    );
    await repo.add(
      amount: Money.parse('50'),
      categoryId: 1,
      date: DateTime(2026, 3, 6),
    );
    await repo.add(
      amount: Money.parse('200'),
      categoryId: 2,
      date: DateTime(2026, 3, 7),
    );
    final (start, end) = monthBounds(DateTime(2026, 3, 1));
    final totals = await repo.totalsByCategory(start, end);
    expect(totals[1], Money.fromMinor(15000));
    expect(totals[2], Money.fromMinor(20000));
  });

  test('watchTotalsByCategory re-emits after a new expense is added', () async {
    final (start, end) = monthBounds(DateTime(2026, 3, 1));
    final stream = repo.watchTotalsByCategory(start, end);
    final emissions = <Map<int, Money>>[];
    final sub = stream.listen(emissions.add);
    await pumpEventQueue();
    await repo.add(
      amount: Money.parse('75'),
      categoryId: 1,
      date: DateTime(2026, 3, 5),
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(emissions.last[1], Money.fromMinor(7500));
  });

  test('monthTotal/totalInRange excludeCategoryIds drops those categories', () async {
    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 5),
    );
    await repo.add(
      amount: Money.parse('50'),
      categoryId: 2,
      date: DateTime(2026, 3, 6),
    );
    final total = await repo.monthTotal(
      DateTime(2026, 3, 1),
      excludeCategoryIds: {1},
    );
    expect(total, Money.fromMinor(5000)); // only category 2's ₹50
  });

  test('watchInRange excludes out-of-range', () async {
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 10),
    );
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 5, 10),
    );
    final rows = await repo
        .watchInRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1))
        .first;
    expect(rows.length, 1);
  });

  test('watchInRange limit caps rows and grows page-by-page', () async {
    for (var d = 1; d <= 250; d++) {
      await repo.add(
        amount: Money.parse('1'),
        categoryId: 1,
        date: DateTime(2026, 3, 1).add(Duration(minutes: d)),
      );
    }
    final start = DateTime(2026, 3, 1);
    final end = DateTime(2026, 4, 1);

    final page1 = await repo.watchInRange(start, end, limit: 100).first;
    expect(page1.length, 100);
    // Newest-first: first row is the latest date.
    expect(page1.first.date.isAfter(page1.last.date), isTrue);

    final page2 = await repo.watchInRange(start, end, limit: 200).first;
    expect(page2.length, 200);
    // Growing the limit is a strict prefix extension — same rows, more of them.
    expect(page2.take(100).map((e) => e.id), page1.map((e) => e.id));

    final all = await repo.watchInRange(start, end).first;
    expect(all.length, 250); // null limit = whole range
  });

  test('watchInRange with categoryIds returns only matching rows', () async {
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
    );
    await repo.add(
      amount: Money.parse('20'),
      categoryId: 2,
      date: DateTime(2026, 3, 2),
    );
    await repo.add(
      amount: Money.parse('30'),
      categoryId: 3,
      date: DateTime(2026, 3, 3),
    );
    final rows = await repo
        .watchInRange(
          DateTime(2026, 3, 1),
          DateTime(2026, 4, 1),
          categoryIds: {1, 3},
        )
        .first;
    expect(rows.map((e) => e.categoryId).toSet(), {1, 3});
  });

  test('watchInRange with accountIds returns only matching rows', () async {
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
      accountId: 1,
    );
    await repo.add(
      amount: Money.parse('20'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
      accountId: 2,
    );
    await repo.add(
      // No account at all — must not match either filter.
      amount: Money.parse('30'),
      categoryId: 1,
      date: DateTime(2026, 3, 3),
    );
    final rows = await repo
        .watchInRange(
          DateTime(2026, 3, 1),
          DateTime(2026, 4, 1),
          accountIds: {1},
        )
        .first;
    expect(rows.map((e) => e.amountMinor), [Money.parse('10').minor]);
  });

  test(
    'distinctCategoryIdsInRange returns only categories actually used',
    () async {
      await repo.add(
        amount: Money.parse('10'),
        categoryId: 1,
        date: DateTime(2026, 3, 1),
      );
      await repo.add(
        amount: Money.parse('20'),
        categoryId: 1,
        date: DateTime(2026, 3, 2),
      );
      await repo.add(
        amount: Money.parse('30'),
        categoryId: 2,
        date: DateTime(2026, 3, 3),
      );
      // Category 3 has an expense outside the range — must not appear.
      await repo.add(
        amount: Money.parse('40'),
        categoryId: 3,
        date: DateTime(2026, 5, 1),
      );
      final ids = await repo
          .distinctCategoryIdsInRange(
            DateTime(2026, 3, 1),
            DateTime(2026, 4, 1),
          )
          .first;
      expect(ids, {1, 2});
    },
  );

  test('update and delete reflected', () async {
    final id = await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 10),
    );
    await repo.update(id, amount: Money.parse('175'));
    var rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    expect(rows.single.amount, Money.fromMinor(17500));

    await repo.delete(id);
    rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    expect(rows, isEmpty);
  });

  test('empty month totals to zero, not null', () async {
    expect(await repo.monthTotal(DateTime(2026, 9, 1)), Money.zero);
  });

  test('add accepts an optional tagId, defaults to untagged', () async {
    final untaggedId = await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
    );
    final taggedId = await repo.add(
      amount: Money.parse('20'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
      tagId: 1,
    );
    final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
    expect(rows.firstWhere((e) => e.id == untaggedId).tagId, isNull);
    expect(rows.firstWhere((e) => e.id == taggedId).tagId, 1);
  });

  test('update can set and clear tagId', () async {
    final id = await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
    );
    await repo.update(id, tagId: const Value(1));
    var row = (await repo.watchMonth(DateTime(2026, 3, 1)).first).single;
    expect(row.tagId, 1);

    await repo.update(id, tagId: const Value(null));
    row = (await repo.watchMonth(DateTime(2026, 3, 1)).first).single;
    expect(row.tagId, isNull);
  });

  test(
    'watchTotalsByTag groups correctly and ignores untagged expenses',
    () async {
      await repo.add(
        amount: Money.parse('100'),
        categoryId: 1,
        date: DateTime(2026, 3, 5),
        tagId: 1,
      );
      await repo.add(
        amount: Money.parse('50'),
        categoryId: 2,
        date: DateTime(2026, 3, 6),
        tagId: 1,
      );
      await repo.add(
        amount: Money.parse('200'),
        categoryId: 1,
        date: DateTime(2026, 3, 7),
      );
      final totals = await repo.watchTotalsByTag().first;
      expect(totals[1], Money.fromMinor(15000));
      expect(totals.containsKey(null), isFalse);
    },
  );

  test('watchTotalsByTag emits an updated total after a later add', () async {
    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 5),
      tagId: 1,
    );
    final stream = repo.watchTotalsByTag();
    expect(await stream.first, {1: Money.fromMinor(10000)});

    await repo.add(
      amount: Money.parse('50'),
      categoryId: 1,
      date: DateTime(2026, 3, 6),
      tagId: 1,
    );
    expect(await stream.first, {1: Money.fromMinor(15000)});
  });

  test('watchCountByTag counts only expenses with that tag', () async {
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
      tagId: 1,
    );
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
      tagId: 1,
    );
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 3),
    );
    expect(await repo.watchCountByTag(1).first, 2);
    expect(await repo.watchCountByTag(2).first, 0);
  });

  test('watchCountByTag emits an updated count after a later add', () async {
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
      tagId: 1,
    );
    final stream = repo.watchCountByTag(1);
    expect(await stream.first, 1);

    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
      tagId: 1,
    );
    expect(await stream.first, 2);
  });

  test('watchByTag returns only expenses with that tag', () async {
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
      tagId: 1,
    );
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
      tagId: 2,
    );
    await repo.add(
      amount: Money.parse('10'),
      categoryId: 1,
      date: DateTime(2026, 3, 3),
    );
    final rows = await repo.watchByTag(1).first;
    expect(rows.length, 1);
    expect(rows.single.tagId, 1);
  });

  test('earliestExpenseDate is null with no expenses, else the oldest date', () async {
    expect(await repo.earliestExpenseDate(), isNull);

    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 10),
    );
    await repo.add(
      amount: Money.parse('200'),
      categoryId: 1,
      date: DateTime(2026, 1, 5),
    );
    await repo.add(
      amount: Money.parse('50'),
      categoryId: 2,
      date: DateTime(2026, 2, 1),
    );

    expect(await repo.earliestExpenseDate(), DateTime(2026, 1, 5));
  });

  group('restore (undo a delete)', () {
    Future<ExpenseRow> seed() async {
      final id = await repo.add(
        amount: Money.parse('24.35'),
        categoryId: 2,
        date: DateTime(2026, 3, 10),
        note: 'lunch',
        paymentMethod: 'UPI',
        fxCurrency: 'THB',
        fxAmount: Money.parse('100'),
      );
      final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
      return rows.firstWhere((e) => e.id == id);
    }

    test('brings the row back byte-for-byte', () async {
      final original = await seed();
      await repo.delete(original.id);
      expect(await repo.watchMonth(DateTime(2026, 3, 1)).first, isEmpty);

      await repo.restore(original);

      final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
      expect(rows, hasLength(1));
      // Every field, not just the amount — an undo that quietly drops the note
      // or the FX receipt is a data-loss bug wearing an undo button.
      expect(rows.single, original);
    });

    test('keeps the same externalId so backup Merge identity survives',
        () async {
      final original = await seed();
      await repo.delete(original.id);
      await repo.restore(original);

      final restored =
          (await repo.watchMonth(DateTime(2026, 3, 1)).first).single;
      expect(restored.externalId, original.externalId);
      expect(restored.externalId, isNotNull);
    });

    test('keeps its original id, so ids never silently shuffle', () async {
      final original = await seed();
      await repo.delete(original.id);
      // A row added during the undo window must not be able to take the id
      // back (SQLite AUTOINCREMENT guarantees this — asserted, not assumed).
      await repo.add(
        amount: Money.parse('5'),
        categoryId: 1,
        date: DateTime(2026, 3, 11),
      );

      await repo.restore(original);

      final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
      expect(rows.map((e) => e.id), containsAll([original.id]));
      expect(rows, hasLength(2));
    });
  });

  group('topNotes', () {
    test('most-frequently-used note comes first', () async {
      for (var i = 0; i < 3; i++) {
        await repo.add(
          amount: Money.parse('10'),
          categoryId: 1,
          date: DateTime(2026, 3, i + 1),
          note: 'Coffee',
        );
      }
      await repo.add(
        amount: Money.parse('10'),
        categoryId: 1,
        date: DateTime(2026, 3, 10),
        note: 'Gas',
      );
      final notes = await repo.topNotes();
      expect(notes.first, 'Coffee');
      expect(notes, contains('Gas'));
    });

    test('a note used on multiple expenses appears only once', () async {
      await repo.add(
        amount: Money.parse('10'),
        categoryId: 1,
        date: DateTime(2026, 3, 1),
        note: 'Coffee',
      );
      await repo.add(
        amount: Money.parse('10'),
        categoryId: 1,
        date: DateTime(2026, 3, 2),
        note: 'Coffee',
      );
      expect(await repo.topNotes(), ['Coffee']);
    });

    test('expenses with no note are excluded', () async {
      await repo.add(amount: Money.parse('10'), categoryId: 1, date: DateTime(2026, 3, 1));
      expect(await repo.topNotes(), isEmpty);
    });

    test('respects the limit', () async {
      for (final note in ['A', 'B', 'C']) {
        await repo.add(
          amount: Money.parse('10'),
          categoryId: 1,
          date: DateTime(2026, 3, 1),
          note: note,
        );
      }
      expect(await repo.topNotes(limit: 2), hasLength(2));
    });
  });

  group('addWithRecurrence', () {
    test('the real transaction is never itself flagged recurring', () async {
      final id = await repo.addWithRecurrence(
        amount: Money.parse('199'),
        categoryId: 1,
        date: DateTime(2026, 3, 3),
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 4, 3),
      );
      final rows = await repo.watchMonth(DateTime(2026, 3, 1)).first;
      final real = rows.firstWhere((e) => e.id == id);
      expect(real.isRecurring, isFalse);
      expect(real.templateOnly, isFalse);
    });

    test('a separate template-only row carries the schedule', () async {
      await repo.addWithRecurrence(
        amount: Money.parse('199'),
        categoryId: 1,
        date: DateTime(2026, 3, 3),
        note: 'Netflix',
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 4, 3),
      );
      final all = await (db.select(db.expenses)).get();
      expect(all, hasLength(2));
      final template = all.firstWhere((e) => e.templateOnly);
      expect(template.isRecurring, isTrue);
      expect(template.recurrence, Recurrence.monthly);
      expect(template.nextDueDate, DateTime(2026, 4, 3));
      expect(template.note, 'Netflix');
    });

    test('the template-only row is excluded from the month total', () async {
      await repo.addWithRecurrence(
        amount: Money.parse('199'),
        categoryId: 1,
        date: DateTime(2026, 3, 3),
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 4, 3),
      );
      // Only the real ₹199 transaction counts — not doubled by its template.
      expect(await repo.monthTotal(DateTime(2026, 3, 1)), Money.parse('199'));
    });

    test('no recurrence set behaves like a plain add — no second row', () async {
      await repo.addWithRecurrence(
        amount: Money.parse('50'),
        categoryId: 1,
        date: DateTime(2026, 3, 3),
      );
      expect(await (db.select(db.expenses)).get(), hasLength(1));
    });
  });

  group('updateWithRecurrence', () {
    test(
      'turning recurrence on for a plain expense keeps it a plain, '
      'non-recurring row and spawns a separate template instead',
      () async {
        final id = await repo.add(
          amount: Money.parse('199'),
          categoryId: 1,
          date: DateTime(2026, 3, 3),
        );
        await repo.updateWithRecurrence(
          id: id,
          amount: Money.parse('199'),
          categoryId: 1,
          date: DateTime(2026, 3, 3),
          recurrence: Recurrence.monthly,
          nextDueDate: DateTime(2026, 4, 3),
        );

        final original = await (db.select(
          db.expenses,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(original.isRecurring, isFalse);
        expect(original.templateOnly, isFalse);

        final all = await (db.select(db.expenses)).get();
        expect(all, hasLength(2));
        final template = all.firstWhere((e) => e.id != id);
        expect(template.templateOnly, isTrue);
        expect(template.isRecurring, isTrue);
      },
    );

    test(
      'editing the spawned template later never touches the original '
      'transaction',
      () async {
        final id = await repo.add(
          amount: Money.parse('199'),
          categoryId: 1,
          date: DateTime(2026, 3, 3),
        );
        await repo.updateWithRecurrence(
          id: id,
          amount: Money.parse('199'),
          categoryId: 1,
          date: DateTime(2026, 3, 3),
          recurrence: Recurrence.monthly,
          nextDueDate: DateTime(2026, 4, 3),
        );
        final template = (await (db.select(
          db.expenses,
        )).get()).firstWhere((e) => e.id != id);

        // Editing "the rule" — e.g. Netflix's price went up — via the plain
        // update() a template row uses, exactly like editing any other row.
        await repo.update(template.id, amount: Money.parse('249'));

        final original = await (db.select(
          db.expenses,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(original.amount, Money.parse('199'));
      },
    );
  });
}

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
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';

CategoryRow _cat(int id, String name) => CategoryRow(
  id: id,
  name: name,
  icon: '🍔',
  colorValue: 0xFF000000,
  sortOrder: id,
  isArchived: false,
  isDefault: false,
  isIgnoredForBudget: false,
);

void main() {
  group('parseExpenseQuery', () {
    final categories = [_cat(1, 'Food'), _cat(2, 'Fuel'), _cat(3, 'Groceries')];

    test('blank input matches nothing at all', () {
      for (final blank in ['', '   ']) {
        final q = parseExpenseQuery(blank, categories);
        expect(q.text, isNull);
        expect(q.amountMinor, isNull);
        expect(q.categoryIds, isEmpty);
      }
    });

    test('plain text is a note match with no amount', () {
      final q = parseExpenseQuery('lunch', categories);
      expect(q.text, 'lunch');
      expect(q.amountMinor, isNull);
      expect(q.categoryIds, isEmpty);
    });

    test('a number also becomes an exact amount match', () {
      expect(parseExpenseQuery('240', categories).amountMinor, 24000);
      expect(parseExpenseQuery('24.35', categories).amountMinor, 2435);
    });

    test('a non-numeric query does not blow up on the amount parse', () {
      // Money.parse throws FormatException on this — the search must survive
      // it, since most queries are words.
      expect(parseExpenseQuery('coffee', categories).amountMinor, isNull);
    });

    test('zero is not treated as an amount to match', () {
      expect(parseExpenseQuery('0', categories).amountMinor, isNull);
    });

    test('category names match case-insensitively and partially', () {
      expect(parseExpenseQuery('foo', categories).categoryIds, {1});
      expect(parseExpenseQuery('FU', categories).categoryIds, {2});
      // "o" appears in Food and Groceries, not Fuel.
      expect(parseExpenseQuery('o', categories).categoryIds, {1, 3});
    });

    test('surrounding whitespace is trimmed before matching', () {
      final q = parseExpenseQuery('  Food  ', categories);
      expect(q.text, 'Food');
      expect(q.categoryIds, {1});
    });
  });

  group('watchInRange search', () {
    late AppDatabase db;
    late ExpenseRepository repo;
    late List<CategoryRow> categories;
    final range = (DateTime(2026, 3, 1), DateTime(2026, 4, 1));

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ExpenseRepository(db);
      categories = await CategoryRepository(db).watchAll().first;
    });
    tearDown(() => db.close());

    /// Seeds three rows in March: a noted coffee, an un-noted row in the same
    /// category, and one in a different category.
    Future<void> seed() async {
      await repo.add(
        amount: Money.parse('240'),
        categoryId: categories[0].id,
        date: DateTime(2026, 3, 5),
        note: 'Morning coffee',
      );
      await repo.add(
        amount: Money.parse('99.50'),
        categoryId: categories[0].id,
        date: DateTime(2026, 3, 6),
      );
      await repo.add(
        amount: Money.parse('1200'),
        categoryId: categories[1].id,
        date: DateTime(2026, 3, 7),
        note: 'Airport cab',
      );
    }

    Future<List<ExpenseRow>> search(String raw) => repo
        .watchInRange(
          range.$1,
          range.$2,
          search: parseExpenseQuery(raw, categories),
        )
        .first;

    test('no search returns everything in range', () async {
      await seed();
      expect(await search(''), hasLength(3));
    });

    test('matches note text case-insensitively', () async {
      await seed();
      final rows = await search('COFFEE');
      expect(rows.map((e) => e.note), ['Morning coffee']);
    });

    test('matches a note substring, not just a prefix', () async {
      await seed();
      expect(await search('cab'), hasLength(1));
    });

    test('matches an exact amount', () async {
      await seed();
      final rows = await search('99.50');
      expect(rows.single.amountMinor, 9950);
    });

    test('an amount match finds rows with no note at all', () async {
      // The un-noted row can only be reached by amount or category — a
      // note-only search would silently never return it.
      await seed();
      final rows = await search('99.50');
      expect(rows.single.note, isNull);
    });

    test('matches by category name', () async {
      await seed();
      final rows = await search(categories[1].name);
      expect(rows.map((e) => e.categoryId), everyElement(categories[1].id));
      expect(rows, hasLength(1));
    });

    test('the three match kinds are ORed, not ANDed', () async {
      await seed();
      // "240" is an amount on row 1; it is not in any note or category name.
      // "coffee" is a note. A query hitting either kind must return a row.
      expect(await search('240'), hasLength(1));
      expect(await search('coffee'), hasLength(1));
    });

    test('stays inside the date range', () async {
      await seed();
      await repo.add(
        amount: Money.parse('240'),
        categoryId: categories[0].id,
        date: DateTime(2026, 2, 20),
        note: 'Morning coffee',
      );
      // Same note and amount, but in February — the range still wins.
      expect(await search('coffee'), hasLength(1));
    });

    test('combines with an explicit category filter using AND', () async {
      await seed();
      final rows = await repo
          .watchInRange(
            range.$1,
            range.$2,
            categoryIds: {categories[1].id},
            search: parseExpenseQuery('coffee', categories),
          )
          .first;
      // The coffee row is in category 0, so filtering to category 1 excludes
      // it — the filter narrows the search rather than widening it.
      expect(rows, isEmpty);
    });

    test('a search that matches nothing returns empty, not everything',
        () async {
      await seed();
      expect(await search('zzzz'), isEmpty);
    });
  });
}

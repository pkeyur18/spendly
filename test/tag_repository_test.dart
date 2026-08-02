import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/tags/tag_repository.dart';

void main() {
  late AppDatabase db;
  late TagRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TagRepository(db);
  });
  tearDown(() => db.close());

  test('starts with no tags', () async {
    final tags = await repo.watchAll().first;
    expect(tags, isEmpty);
  });

  test('create adds a tag visible in watchAll and watchActive', () async {
    final id = await repo.create(name: 'Japan Trip', colorValue: 0xFF6366F1);
    final all = await repo.watchAll().first;
    final active = await repo.watchActive().first;
    expect(all.single.id, id);
    expect(all.single.name, 'Japan Trip');
    expect(active.single.id, id);
  });

  test(
    'archive hides a tag from watchActive but keeps it in watchAll',
    () async {
      final id = await repo.create(name: 'Japan Trip', colorValue: 0xFF6366F1);
      await repo.archive(id);
      final all = await repo.watchAll().first;
      final active = await repo.watchActive().first;
      expect(all.any((t) => t.id == id), isTrue);
      expect(active.any((t) => t.id == id), isFalse);
    },
  );

  test('unarchive restores a tag to watchActive', () async {
    final id = await repo.create(name: 'Japan Trip', colorValue: 0xFF6366F1);
    await repo.archive(id);
    await repo.unarchive(id);
    final active = await repo.watchActive().first;
    expect(active.any((t) => t.id == id), isTrue);
  });

  test('rename and recolor update the tag', () async {
    final id = await repo.create(name: 'Japan Trip', colorValue: 0xFF6366F1);
    await repo.rename(id, 'Japan Trip 2026');
    await repo.recolor(id, 0xFF14B8A6);
    final tag = (await repo.watchAll().first).single;
    expect(tag.name, 'Japan Trip 2026');
    expect(tag.colorValue, 0xFF14B8A6);
  });

  test('delete removes the tag but leaves its expenses, untagged', () async {
    final id = await repo.create(name: 'Japan Trip', colorValue: 0xFF6366F1);
    final expenseId = await ExpenseRepository(db).add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 1),
      tagId: id,
    );

    await repo.delete(id);

    final tags = await repo.watchAll().first;
    expect(tags.any((t) => t.id == id), isFalse);

    final expenses = await db.select(db.expenses).get();
    final expense = expenses.firstWhere((e) => e.id == expenseId);
    expect(expense.tagId, isNull);
  });

  group('trip dates', () {
    test('create stores a date range and setTripDates updates it', () async {
      final id = await repo.create(
        name: 'Thailand',
        colorValue: 0xFFF59E0B,
        tripStartDate: DateTime(2026, 3, 1),
        tripEndDate: DateTime(2026, 3, 10),
      );
      var tag = await repo.byId(id);
      expect(tag!.tripStartDate, DateTime(2026, 3, 1));
      expect(tag.tripEndDate, DateTime(2026, 3, 10));

      await repo.setTripDates(id, DateTime(2026, 3, 2), DateTime(2026, 3, 12));
      tag = await repo.byId(id);
      expect(tag!.tripStartDate, DateTime(2026, 3, 2));
      expect(tag.tripEndDate, DateTime(2026, 3, 12));

      await repo.setTripDates(id, null, null);
      tag = await repo.byId(id);
      expect(tag!.tripStartDate, isNull);
      expect(tag.tripEndDate, isNull);
    });

    test('tripForDate matches inclusive boundaries and misses outside them', () async {
      final id = await repo.create(
        name: 'Thailand',
        colorValue: 0xFFF59E0B,
        tripStartDate: DateTime(2026, 3, 1),
        tripEndDate: DateTime(2026, 3, 10),
      );

      expect((await repo.tripForDate(DateTime(2026, 3, 1)))?.id, id);
      expect((await repo.tripForDate(DateTime(2026, 3, 10)))?.id, id);
      expect((await repo.tripForDate(DateTime(2026, 3, 5)))?.id, id);
      expect(await repo.tripForDate(DateTime(2026, 2, 28)), isNull);
      expect(await repo.tripForDate(DateTime(2026, 3, 11)), isNull);
    });

    test('tripForDate ignores archived trips', () async {
      final id = await repo.create(
        name: 'Thailand',
        colorValue: 0xFFF59E0B,
        tripStartDate: DateTime(2026, 3, 1),
        tripEndDate: DateTime(2026, 3, 10),
      );
      await repo.archive(id);
      expect(await repo.tripForDate(DateTime(2026, 3, 5)), isNull);
    });

    test('tripForDate ignores a tag with no date range', () async {
      await repo.create(name: 'Groceries', colorValue: 0xFF6366F1);
      expect(await repo.tripForDate(DateTime(2026, 3, 5)), isNull);
    });

    test('hasOverlappingDateRange detects any-day overlap', () async {
      await repo.create(
        name: 'Thailand',
        colorValue: 0xFFF59E0B,
        tripStartDate: DateTime(2026, 3, 1),
        tripEndDate: DateTime(2026, 3, 10),
      );

      expect(
        await repo.hasOverlappingDateRange(
          null,
          DateTime(2026, 3, 8),
          DateTime(2026, 3, 15),
        ),
        isTrue,
      );
      expect(
        await repo.hasOverlappingDateRange(
          null,
          DateTime(2026, 3, 10),
          DateTime(2026, 3, 10),
        ),
        isTrue,
        reason: 'a single shared boundary day still counts as overlap',
      );
    });

    test('hasOverlappingDateRange allows adjacent, non-overlapping ranges', () async {
      await repo.create(
        name: 'Thailand',
        colorValue: 0xFFF59E0B,
        tripStartDate: DateTime(2026, 3, 1),
        tripEndDate: DateTime(2026, 3, 10),
      );

      expect(
        await repo.hasOverlappingDateRange(
          null,
          DateTime(2026, 3, 11),
          DateTime(2026, 3, 15),
        ),
        isFalse,
      );
    });

    test('hasOverlappingDateRange excludes the tag being edited', () async {
      final id = await repo.create(
        name: 'Thailand',
        colorValue: 0xFFF59E0B,
        tripStartDate: DateTime(2026, 3, 1),
        tripEndDate: DateTime(2026, 3, 10),
      );

      // Editing the same trip's own dates must not collide with itself.
      expect(
        await repo.hasOverlappingDateRange(
          id,
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 12),
        ),
        isFalse,
      );
    });
  });
}

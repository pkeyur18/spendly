import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/goals/goal_repository.dart';

void main() {
  late AppDatabase db;
  late GoalRepository goals;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    goals = GoalRepository(db);
  });
  tearDown(() => db.close());

  test('create then read back exact fields', () async {
    final id = await goals.create(
      name: 'New laptop',
      target: Money.parse('80000'),
    );
    final row = await goals.byId(id);
    expect(row!.name, 'New laptop');
    expect(row.targetMinor, Money.parse('80000').minor);
    expect(row.savedMinor, 0);
    expect(row.isArchived, isFalse);
    expect(row.externalId, isNotNull);
  });

  test('update changes only the given fields', () async {
    final id = await goals.create(name: 'Old name', target: Money.parse('1000'));
    await goals.update(id, name: 'New name');
    final row = await goals.byId(id);
    expect(row!.name, 'New name');
    expect(row.targetMinor, Money.parse('1000').minor); // untouched
  });

  group('adjustSaved', () {
    test('a positive delta adds to the saved total', () async {
      final id = await goals.create(name: 'Goal', target: Money.parse('1000'));
      await goals.adjustSaved(id, Money.parse('300'));
      expect((await goals.byId(id))!.savedMinor, Money.parse('300').minor);
    });

    test('a negative delta withdraws from the saved total', () async {
      final id = await goals.create(name: 'Goal', target: Money.parse('1000'));
      await goals.adjustSaved(id, Money.parse('300'));
      await goals.adjustSaved(id, Money.fromMinor(-Money.parse('100').minor));
      expect((await goals.byId(id))!.savedMinor, Money.parse('200').minor);
    });

    test('clamps at zero — a withdrawal larger than the saved total never '
        'goes negative', () async {
      final id = await goals.create(name: 'Goal', target: Money.parse('1000'));
      await goals.adjustSaved(id, Money.parse('100'));
      await goals.adjustSaved(id, Money.fromMinor(-Money.parse('500').minor));
      expect((await goals.byId(id))!.savedMinor, 0);
    });
  });

  group('archive', () {
    test('setArchived(true) hides it from watchActive but keeps the row',
        () async {
      final keep = await goals.create(name: 'Keep', target: Money.parse('100'));
      final archive = await goals.create(
        name: 'Archive',
        target: Money.parse('100'),
      );
      await goals.setArchived(archive, true);

      final active = await goals.watchActive().first;
      expect(active.map((g) => g.id), [keep]);
      expect(await goals.watchAll().first, hasLength(2));
    });

    test('setArchived(false) restores it', () async {
      final id = await goals.create(name: 'Goal', target: Money.parse('100'));
      await goals.setArchived(id, true);
      await goals.setArchived(id, false);
      expect((await goals.byId(id))!.isArchived, isFalse);
    });
  });

  group('progressRatio / isComplete (row_extensions)', () {
    test('ratio is saved over target, clamped at 1.0', () async {
      final id = await goals.create(name: 'Goal', target: Money.parse('1000'));
      await goals.adjustSaved(id, Money.parse('1500')); // exceeds target
      final row = (await goals.byId(id))!;
      expect(row.progressRatio, 1.0);
      expect(row.isComplete, isTrue);
    });

    test('partial progress ratio', () async {
      final id = await goals.create(name: 'Goal', target: Money.parse('1000'));
      await goals.adjustSaved(id, Money.parse('250'));
      final row = (await goals.byId(id))!;
      expect(row.progressRatio, 0.25);
      expect(row.isComplete, isFalse);
    });
  });

  test('delete removes the row entirely', () async {
    final id = await goals.create(name: 'Goal', target: Money.parse('100'));
    await goals.delete(id);
    expect(await goals.byId(id), isNull);
  });
}

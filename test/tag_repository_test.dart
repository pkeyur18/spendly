import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
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
}

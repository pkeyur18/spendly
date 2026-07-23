import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/features/profile/profile_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  test('defaults to blank profile', () async {
    final profile = await container.read(profileProvider.future);
    expect(profile.name, '');
    expect(profile.email, '');
    expect(profile.phone, '');
    expect(profile.isEmpty, isTrue);
  });

  test('save persists and reload returns it', () async {
    await container.read(profileProvider.future); // settle initial build
    await container
        .read(profileProvider.notifier)
        .save(
          const Profile(
            name: 'Ada Lovelace',
            email: 'ada@example.com',
            phone: '555-0100',
          ),
        );

    container.invalidate(profileProvider);
    final reloaded = await container.read(profileProvider.future);
    expect(reloaded.name, 'Ada Lovelace');
    expect(reloaded.email, 'ada@example.com');
    expect(reloaded.phone, '555-0100');
    expect(reloaded.isEmpty, isFalse);
  });
}

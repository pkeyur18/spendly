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

  test('name-only save clears the gate; resetToDefaults reinstates it', () async {
    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(const Profile(name: 'Ada')); // phone/email blank — optional per FR-45
    expect(container.read(profileProvider).value!.name.isEmpty, isFalse);

    await db.resetToDefaults();
    container.invalidate(profileProvider);
    final reloaded = await container.read(profileProvider.future);
    expect(reloaded.name.isEmpty, isTrue); // onboarding must reappear (FR-50)
  });

  test('avatar photoPath/avatarColorIndex persist and reload (FR-51..55)', () async {
    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(
          const Profile(
            name: 'Ada',
            photoPath: '/tmp/avatar.jpg',
            avatarColorIndex: 2,
          ),
        );

    container.invalidate(profileProvider);
    final reloaded = await container.read(profileProvider.future);
    expect(reloaded.photoPath, '/tmp/avatar.jpg');
    expect(reloaded.avatarColorIndex, 2);
  });

  test('copyWith can clear photoPath/avatarColorIndex independently', () {
    const withAvatar = Profile(
      name: 'Ada',
      photoPath: '/tmp/avatar.jpg',
      avatarColorIndex: 2,
    );
    final colorOnly = withAvatar.copyWith(clearPhotoPath: true, avatarColorIndex: 3);
    expect(colorOnly.photoPath, isNull);
    expect(colorOnly.avatarColorIndex, 3);

    final photoOnly = withAvatar.copyWith(clearAvatarColorIndex: true);
    expect(photoOnly.photoPath, '/tmp/avatar.jpg');
    expect(photoOnly.avatarColorIndex, isNull);
  });

  test('resetToDefaults clears avatar fields too', () async {
    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(
          const Profile(
            name: 'Ada',
            photoPath: '/tmp/avatar.jpg',
            avatarColorIndex: 2,
          ),
        );

    await db.resetToDefaults();
    container.invalidate(profileProvider);
    final reloaded = await container.read(profileProvider.future);
    expect(reloaded.photoPath, isNull);
    expect(reloaded.avatarColorIndex, isNull);
  });
}

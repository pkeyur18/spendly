import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  test('avatar photoBytes/avatarColorIndex persist and reload (FR-51..55)', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(Profile(name: 'Ada', photoBytes: bytes, avatarColorIndex: 2));

    container.invalidate(profileProvider);
    final reloaded = await container.read(profileProvider.future);
    expect(reloaded.photoBytes, bytes);
    expect(reloaded.avatarColorIndex, 2);
  });

  test('copyWith can clear photoBytes/avatarColorIndex independently', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final withAvatar = Profile(name: 'Ada', photoBytes: bytes, avatarColorIndex: 2);
    final colorOnly = withAvatar.copyWith(clearPhotoBytes: true, avatarColorIndex: 3);
    expect(colorOnly.photoBytes, isNull);
    expect(colorOnly.avatarColorIndex, 3);

    final photoOnly = withAvatar.copyWith(clearAvatarColorIndex: true);
    expect(photoOnly.photoBytes, bytes);
    expect(photoOnly.avatarColorIndex, isNull);
  });

  test('resetToDefaults clears avatar fields too', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(Profile(name: 'Ada', photoBytes: bytes, avatarColorIndex: 2));

    await db.resetToDefaults();
    container.invalidate(profileProvider);
    final reloaded = await container.read(profileProvider.future);
    expect(reloaded.photoBytes, isNull);
    expect(reloaded.avatarColorIndex, isNull);
  });

  test('migrates a legacy on-disk photo path to base64 bytes, then cleans up', () async {
    final tempDir = await Directory.systemTemp.createTemp('avatar_migration');
    addTearDown(() => tempDir.delete(recursive: true));
    final legacyFile = File(p.join(tempDir.path, 'avatar.jpg'));
    final bytes = Uint8List.fromList([9, 8, 7, 6]);
    await legacyFile.writeAsBytes(bytes);

    final settings = container.read(settingsRepositoryProvider);
    await settings.set(SettingsRepository.profilePhotoPathKey, legacyFile.path);

    final profile = await container.read(profileProvider.future);
    expect(profile.photoBytes, bytes);
    expect(await legacyFile.exists(), isFalse); // migrated bytes in, file cleaned up
    expect(
      await settings.get(SettingsRepository.profilePhotoBase64Key),
      isNotNull,
    );
    expect(await settings.get(SettingsRepository.profilePhotoPathKey), isNull);
  });

  test('legacy photo path pointing at a missing file is dropped, not crashed on', () async {
    final settings = container.read(settingsRepositoryProvider);
    await settings.set(
      SettingsRepository.profilePhotoPathKey,
      '/does/not/exist/avatar.jpg',
    );

    final profile = await container.read(profileProvider.future);
    expect(profile.photoBytes, isNull);
    expect(await settings.get(SettingsRepository.profilePhotoPathKey), isNull);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';

/// User's own details (FR: shown on generated reports) plus avatar choice
/// (FR-51..55). All fields optional except that onboarding gates on [name].
class Profile {
  const Profile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.photoBytes,
    this.avatarColorIndex,
  });

  final String name;
  final String email;
  final String phone;

  /// Uploaded photo's raw bytes (FR-53), stored as base64 in [Settings] —
  /// same row-store as every other profile field, so it survives exactly as
  /// reliably as they do. Takes precedence over [avatarColorIndex] when
  /// rendering — see `avatar.dart`.
  final Uint8List? photoBytes;

  /// Index into `avatarGradients` (FR-54); null = default gradient (index 0).
  final int? avatarColorIndex;

  bool get isEmpty => name.isEmpty && email.isEmpty && phone.isEmpty;

  Profile copyWith({
    String? name,
    String? email,
    String? phone,
    Uint8List? photoBytes,
    bool clearPhotoBytes = false,
    int? avatarColorIndex,
    bool clearAvatarColorIndex = false,
  }) => Profile(
    name: name ?? this.name,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    photoBytes: clearPhotoBytes ? null : (photoBytes ?? this.photoBytes),
    avatarColorIndex: clearAvatarColorIndex
        ? null
        : (avatarColorIndex ?? this.avatarColorIndex),
  );
}

/// Persisted in the [SettingsRepository] key/value store — same pattern as
/// [ThemeModeNotifier] (theme_mode_provider.dart).
class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    final name = await settings.get(SettingsRepository.profileNameKey);
    final email = await settings.get(SettingsRepository.profileEmailKey);
    final phone = await settings.get(SettingsRepository.profilePhoneKey);
    final photoBytes = await _readOrMigratePhoto(settings);
    final colorRaw = await settings.get(
      SettingsRepository.profileAvatarColorKey,
    );
    return Profile(
      name: name ?? '',
      email: email ?? '',
      phone: phone ?? '',
      photoBytes: photoBytes,
      avatarColorIndex: colorRaw == null ? null : int.tryParse(colorRaw),
    );
  }

  /// Reads the photo from its current base64 key. Falls back to a one-time
  /// migration from the legacy on-disk-file-path key for installs upgrading
  /// from before this photo was stored as bytes in [Settings] directly.
  Future<Uint8List?> _readOrMigratePhoto(SettingsRepository settings) async {
    final base64Data = await settings.get(
      SettingsRepository.profilePhotoBase64Key,
    );
    if (base64Data != null) return base64Decode(base64Data);

    final legacyPath = await settings.get(
      SettingsRepository.profilePhotoPathKey,
    );
    if (legacyPath == null) return null;

    final file = File(legacyPath);
    if (!await file.exists()) {
      await settings.set(SettingsRepository.profilePhotoPathKey, null);
      return null;
    }

    final bytes = await file.readAsBytes();
    await settings.set(
      SettingsRepository.profilePhotoBase64Key,
      base64Encode(bytes),
    );
    await settings.set(SettingsRepository.profilePhotoPathKey, null);
    await file.delete();
    return bytes;
  }

  Future<void> save(Profile profile) async {
    state = AsyncData(profile);
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(SettingsRepository.profileNameKey, profile.name);
    await settings.set(SettingsRepository.profileEmailKey, profile.email);
    await settings.set(SettingsRepository.profilePhoneKey, profile.phone);
    await settings.set(
      SettingsRepository.profilePhotoBase64Key,
      profile.photoBytes == null ? null : base64Encode(profile.photoBytes!),
    );
    await settings.set(
      SettingsRepository.profileAvatarColorKey,
      profile.avatarColorIndex?.toString(),
    );
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);

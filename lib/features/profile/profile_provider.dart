import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';

/// User's own details (FR: shown on generated reports) plus avatar choice
/// (FR-51..55). All fields optional except that onboarding gates on [name].
class Profile {
  const Profile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.photoPath,
    this.avatarColorIndex,
  });

  final String name;
  final String email;
  final String phone;

  /// Local file path to an uploaded photo (FR-53). Takes precedence over
  /// [avatarColorIndex] when rendering — see `avatar.dart`.
  final String? photoPath;

  /// Index into `avatarGradients` (FR-54); null = default gradient (index 0).
  final int? avatarColorIndex;

  bool get isEmpty => name.isEmpty && email.isEmpty && phone.isEmpty;

  Profile copyWith({
    String? name,
    String? email,
    String? phone,
    String? photoPath,
    bool clearPhotoPath = false,
    int? avatarColorIndex,
    bool clearAvatarColorIndex = false,
  }) => Profile(
    name: name ?? this.name,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
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
    final photoPath = await settings.get(
      SettingsRepository.profilePhotoPathKey,
    );
    final colorRaw = await settings.get(
      SettingsRepository.profileAvatarColorKey,
    );
    return Profile(
      name: name ?? '',
      email: email ?? '',
      phone: phone ?? '',
      photoPath: photoPath,
      avatarColorIndex: colorRaw == null ? null : int.tryParse(colorRaw),
    );
  }

  Future<void> save(Profile profile) async {
    state = AsyncData(profile);
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(SettingsRepository.profileNameKey, profile.name);
    await settings.set(SettingsRepository.profileEmailKey, profile.email);
    await settings.set(SettingsRepository.profilePhoneKey, profile.phone);
    await settings.set(
      SettingsRepository.profilePhotoPathKey,
      profile.photoPath,
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

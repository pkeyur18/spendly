import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';

/// User's own details (FR: shown on generated reports). All fields optional.
class Profile {
  const Profile({this.name = '', this.email = '', this.phone = ''});

  final String name;
  final String email;
  final String phone;

  bool get isEmpty => name.isEmpty && email.isEmpty && phone.isEmpty;

  Profile copyWith({String? name, String? email, String? phone}) => Profile(
    name: name ?? this.name,
    email: email ?? this.email,
    phone: phone ?? this.phone,
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
    return Profile(name: name ?? '', email: email ?? '', phone: phone ?? '');
  }

  Future<void> save(Profile profile) async {
    state = AsyncData(profile);
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(SettingsRepository.profileNameKey, profile.name);
    await settings.set(SettingsRepository.profileEmailKey, profile.email);
    await settings.set(SettingsRepository.profilePhoneKey, profile.phone);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);

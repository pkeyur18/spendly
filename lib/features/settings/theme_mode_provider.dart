import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';

/// App theme mode: follows the system by default (NFR), with a manual override
/// persisted in the settings table so it survives restarts.
class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final stored = await ref.read(settingsRepositoryProvider).get(
          SettingsRepository.themeModeKey,
        );
    return _parse(stored);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(settingsRepositoryProvider).set(
          SettingsRepository.themeModeKey,
          mode.name,
        );
  }

  static ThemeMode _parse(String? name) {
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }
}

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

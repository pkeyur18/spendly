import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/db/providers.dart';

/// Thin wrapper over `local_auth` so the rest of the app never imports the
/// plugin directly — same reasoning as `NotificationService` wrapping
/// `flutter_local_notifications`.
class AppLockService {
  final _auth = LocalAuthentication();

  /// False on a device with no biometric enrollment AND no PIN/pattern/
  /// passcode set at all — the App Lock toggle is disabled in that case,
  /// since turning it on would lock the user out with no way back in.
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// True on success. False on a cancel/failed attempt (never throws for
  /// the ordinary "user backed out" case) — [biometricOnly] is false so a
  /// device PIN/pattern/passcode is always an available fallback, matching
  /// the "biometric/PIN" framing this feature was asked for.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Spendly',
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }
}

final appLockServiceProvider = Provider<AppLockService>((ref) => AppLockService());

/// Whether this device can even support App Lock — gates the Profile
/// toggle so it isn't offered somewhere it would strand the user.
final appLockSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockServiceProvider).isSupported(),
);

/// Whether App Lock is turned on, persisted in Settings — same
/// `AsyncNotifier`-over-a-settings-key shape as `AutoBackupSettingsNotifier`.
class AppLockNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    return await settings.get(SettingsRepository.appLockEnabledKey) == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingsRepository.appLockEnabledKey, enabled.toString());
    // Turning it off should never leave the app sitting on a lock screen
    // (there'd be nothing left to unlock with); turning it on re-locks
    // immediately rather than waiting for the next resume.
    ref.read(appUnlockedProvider.notifier).set(!enabled);
  }
}

final appLockEnabledProvider = AsyncNotifierProvider<AppLockNotifier, bool>(
  AppLockNotifier.new,
);

/// In-memory only — never persisted, so every cold start requires unlocking
/// again regardless of how the app was last left. Stays true for the rest
/// of the process once unlocked — backgrounding/resuming (navigation,
/// switching apps, screen timeout) does not re-lock; only actually closing
/// the app does, since a fresh process rebuilds this provider from scratch.
class AppUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final appUnlockedProvider = NotifierProvider<AppUnlockedNotifier, bool>(
  AppUnlockedNotifier.new,
);

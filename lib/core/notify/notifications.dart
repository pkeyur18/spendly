import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local (offline, no server) notifications for budget-threshold alerts
/// (FR-25). Immediate `.show()` only — no scheduling, so no timezone setup.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'budget_alerts';
  static const _channelName = 'Budget alerts';

  /// Call once in `main()` before `runApp`. Sets up the Android channel and
  /// asks for permission (iOS prompt here, Android 13+ prompt below).
  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Fire a budget-crossing alert, e.g. "Food is at 80% of budget".
  Future<void> showBudgetAlert(String label, int pct) {
    final id = label.hashCode ^ pct; // stable-ish per (category, threshold)
    return _plugin.show(
      id: id,
      title: pct >= 100 ? '$label budget reached' : '$label nearing budget',
      body: '$label is at $pct% of its monthly budget',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Alerts when a budget crosses 80% / 100%',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

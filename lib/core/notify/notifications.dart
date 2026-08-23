import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/expenses/recurring_screen.dart';
import '../../features/reports/monthly_report_screen.dart';

/// Lets a tapped notification navigate without a BuildContext. Wired to
/// [MaterialApp.navigatorKey] in app.dart.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Local (offline, no server) notifications: immediate budget-threshold alerts
/// (FR-25) and a monthly-repeating "report ready" reminder (FR-17, FR-18).
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'budget_alerts';
  static const _channelName = 'Budget alerts';
  static const _reportChannelId = 'monthly_report';
  static const _reportChannelName = 'Monthly report';
  static const _reportNotificationId = 424242; // stable id for the repeat
  static const _recurringChannelId = 'recurring_due';
  static const _recurringChannelName = 'Recurring expenses';

  /// Recurring reminders are keyed by `_recurringIdBase + expense id`, so
  /// re-scheduling one replaces its own slot instead of stacking duplicates,
  /// and no id can collide with the monthly report's.
  static const _recurringIdBase = 500000;

  /// Call once in `main()` before `runApp`. Sets up channels, the timezone db
  /// (needed by `zonedSchedule`) and permissions, and the tap handler.
  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(
      tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
    );

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onTap,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// A monthly report notification opens the previous month's report (computed
  /// at tap time so a repeating notification always points at the right month).
  void _onTap(NotificationResponse response) {
    if (response.payload == _recurringChannelId) {
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const RecurringScreen()),
      );
      return;
    }
    if (response.payload != _reportChannelId) return;
    final now = DateTime.now();
    final prevMonth = DateTime(now.year, now.month - 1, 1);
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => MonthlyReportScreen(month: prevMonth)),
    );
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

  /// Schedule a monthly-repeating "report ready" notification for the 1st of
  /// each month at 09:00 local (FR-17, FR-18). Idempotent — the fixed id +
  /// `dayOfMonthAndTime` match just re-arms the same monthly slot. Inexact
  /// scheduling (no SCHEDULE_EXACT_ALARM needed) — a report ping isn't
  /// second-critical. Call once from `main()`.
  Future<void> scheduleMonthlyReport() async {
    await _plugin.zonedSchedule(
      id: _reportNotificationId,
      title: 'Your monthly report is ready 📊',
      body: "Tap to see last month's spending summary.",
      payload: _reportChannelId,
      scheduledDate: _firstOfNextMonthAt9(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _reportChannelId,
          _reportChannelName,
          channelDescription: 'The end-of-month spending report is ready',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  /// Re-arms the due-date reminder for every scheduled recurring expense.
  ///
  /// Called on cold start and on resume rather than from a background job:
  /// this project has no background execution by design (see
  /// `local_auto_backup.dart`), so the schedule is rebuilt whenever the app is
  /// in the user's hands. Every reminder is cancelled first, so a cancelled or
  /// rescheduled series can't leave a stale alarm behind.
  ///
  /// Occurrences already overdue are deliberately NOT scheduled — a past
  /// timestamp would either fire instantly or be dropped, and the Home "to
  /// confirm" card already surfaces them permanently, which a swiped-away
  /// notification does not.
  Future<void> scheduleRecurringReminders(
    List<({int id, String title, DateTime dueAt})> reminders,
  ) async {
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.id >= _recurringIdBase) await _plugin.cancel(id: pending.id);
    }
    final now = tz.TZDateTime.now(tz.local);
    for (final reminder in reminders) {
      final at = tz.TZDateTime(
        tz.local,
        reminder.dueAt.year,
        reminder.dueAt.month,
        reminder.dueAt.day,
        9,
      );
      if (!at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: _recurringIdBase + reminder.id,
        title: '${reminder.title} is due',
        body: 'Tap to confirm it, or skip this one.',
        payload: _recurringChannelId,
        scheduledDate: at,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _recurringChannelId,
            _recurringChannelName,
            channelDescription: 'Reminders for expenses you told us repeat',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    }
  }

  tz.TZDateTime _firstOfNextMonthAt9() {
    final now = tz.TZDateTime.now(tz.local);
    var year = now.year;
    var month = now.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    return tz.TZDateTime(tz.local, year, month, 1, 9);
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/notify/notifications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Notification init/scheduling is deferred to app.dart's post-first-frame
  // hook (Sprint 7) — both do platform-channel round trips (timezone lookup,
  // plugin registration, a possible OS permission prompt) that otherwise block
  // cold start past the 2s NFR budget.
  final notifications = NotificationService();
  runApp(
    ProviderScope(
      overrides: [notificationServiceProvider.overrideWithValue(notifications)],
      child: const SpendlyApp(),
    ),
  );
}

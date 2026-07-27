import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart' show monthKeyFor;
import '../../core/db/providers.dart';
import '../../core/notify/notifications.dart' show appNavigatorKey;
import '../expenses/expense_repository.dart'
    show expenseRepositoryProvider, monthBounds;
import 'monthly_recap_screen.dart';

/// Runs the once-per-calendar-month "auto-show the previous month's recap"
/// check on app launch/resume — same shape as `autoBackupCheckProvider`
/// (`features/backup/backup_providers.dart`), invalidated on resume in
/// `app.dart`'s lifecycle observer.
///
/// Uses a direct one-shot repository read (`listInRange`), not
/// `reportProvider`, for the "anything to recap?" check — per
/// docs/architecture.md §8.1 / `reactive_read_staleness_test.dart`, a
/// Stream/FutureProvider must only ever be consumed via `ref.watch()` inside
/// a widget build, never `ref.read()`'d for one-shot logic like this.
final monthlyRecapCheckProvider = FutureProvider<void>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final now = DateTime.now();
  final currentKey = monthKeyFor(now);
  final lastShown = await settings.get(SettingsRepository.lastRecapMonthKey);
  if (lastShown == currentKey) return; // already shown for this month

  final prevMonth = DateTime(now.year, now.month - 1, 1);
  final (start, end) = monthBounds(prevMonth);
  final expenses = await ref
      .watch(expenseRepositoryProvider)
      .listInRange(start, end);
  if (expenses.isEmpty) return; // nothing to recap (e.g. fresh install)

  appNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => MonthlyRecapScreen(month: prevMonth)),
  );
  await settings.set(SettingsRepository.lastRecapMonthKey, currentKey);
});

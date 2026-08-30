import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart' show monthKeyFor;
import '../../core/db/providers.dart';
import '../../core/notify/notifications.dart' show appNavigatorKey;
import '../../core/theme/app_theme.dart';
import 'budget_repository.dart';
import 'budget_setup_screen.dart';

/// Whether to show the "set next month's budget" nudge right now: only in
/// the last 3 calendar days of the month, only if next month's overall
/// budget is still unset, and only once per month (gated by
/// [lastNudgedMonthKey], the monthKey it last fired for).
bool shouldShowBudgetNudge({
  required DateTime now,
  required bool nextMonthBudgetSet,
  required String? lastNudgedMonthKey,
}) {
  if (nextMonthBudgetSet) return false;
  if (lastNudgedMonthKey == monthKeyFor(now)) return false;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  return now.day > daysInMonth - 3;
}

/// The current time, as seen by [budgetNudgeCheckProvider] — overridden in
/// tests so the "last 3 days of the month" gate doesn't depend on the day
/// the test happens to run on.
final budgetNudgeClockProvider = Provider<DateTime>((ref) => DateTime.now());

/// Runs the once-per-calendar-month "nudge to set next month's budget" check
/// on app launch/resume — same shape as `monthlyRecapCheckProvider`
/// (`features/recap/recap_providers.dart`), invalidated on resume in
/// `app.dart`'s lifecycle observer. Shows a dialog (not a real OS
/// notification — see the design spec's "Nudge type" decision) since this
/// app has no background execution to fire a truly conditional system
/// notification.
final budgetNudgeCheckProvider = FutureProvider<void>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final now = ref.watch(budgetNudgeClockProvider);
  final currentKey = monthKeyFor(now);
  final lastNudged = await settings.get(
    SettingsRepository.lastBudgetNudgeMonthKey,
  );

  final nextMonth = DateTime(now.year, now.month + 1, 1);
  final nextMonthBudget = await ref
      .watch(budgetRepositoryProvider)
      .watchOverallBudget(nextMonth)
      .first;

  if (!shouldShowBudgetNudge(
    now: now,
    nextMonthBudgetSet: nextMonthBudget != null,
    lastNudgedMonthKey: lastNudged,
  )) {
    return;
  }

  await settings.set(SettingsRepository.lastBudgetNudgeMonthKey, currentKey);
  _showBudgetNudgeDialog(nextMonth);
});

/// Not async — kept separate from [budgetNudgeCheckProvider] so this
/// BuildContext use is never textually after an `await` (that combination
/// trips `use_build_context_synchronously`, and there's no `mounted` check
/// available outside a State).
void _showBudgetNudgeDialog(DateTime nextMonth) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Theme(
      data: AppTheme.boldDialogActions(dialogContext),
      child: AlertDialog(
        title: const Text('Set next month\'s budget?'),
        content: const Text(
          'The month is almost over and next month doesn\'t have a budget yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(dialogContext).push(
                MaterialPageRoute(
                  builder: (_) => BudgetSetupScreen(initialMonth: nextMonth),
                ),
              );
            },
            child: const Text('Set it now'),
          ),
        ],
      ),
    ),
  );
}

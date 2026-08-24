import '../../core/db/database.dart';
import 'recurrence.dart';

/// Which occurrences of a recurring expense are waiting on the user, and where
/// the series goes next. Pure — no DB, no notifications.
///
/// The series is tracked by a single `nextDueDate` pointer on the template row
/// rather than by materialising future rows. Occurrences that came and went
/// while the app was closed are therefore not lost: they are everything
/// between the pointer and today, recomputed on demand.

/// Human label for a repeat frequency, shared by the Quick Add picker, the
/// Home due card and the manage list so they can't drift apart.
String recurrenceLabel(Recurrence r) => switch (r) {
  Recurrence.daily => 'Daily',
  Recurrence.weekly => 'Weekly',
  Recurrence.monthly => 'Monthly',
};

/// Ceiling on how many missed occurrences are surfaced at once.
///
/// ponytail: a daily expense left unconfirmed for a year would otherwise
/// produce 365 pending rows — a list nobody will clear and a screen nobody
/// wants. Raise it if a real case needs more; the pointer keeps the rest, so
/// nothing is destroyed by capping the view.
const maxPendingOccurrences = 24;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// One step forward, keeping a monthly series pinned to [anchorDay].
///
/// [nextOccurrence] clamps a short month (Jan 31 → Feb 28) but has no memory
/// of the day it started from, so chaining it drifts permanently: Jan 31 →
/// Feb 28 → Mar 28 → the 28th forever. Rent on the 31st would quietly become
/// rent on the 28th after one February. Re-applying the anchor day each step
/// gives Jan 31 → Feb 28 → Mar 31, clamping only where the month is genuinely
/// too short.
///
/// Daily and weekly need none of this — their period has no month-length
/// dependency.
DateTime _step(DateTime from, Recurrence r, int? anchorDay) {
  final next = nextOccurrence(from, r);
  if (r != Recurrence.monthly || anchorDay == null) return next;
  final lastDay = DateTime(next.year, next.month + 1, 0).day;
  return DateTime(
    next.year,
    next.month,
    anchorDay < lastDay ? anchorDay : lastDay,
    next.hour,
    next.minute,
    next.second,
  );
}

/// Occurrences due on or before [now] and not yet resolved, oldest first.
///
/// Empty when the expense isn't recurring, has ended, or its next occurrence
/// is still in the future — so "is anything waiting?" is just `.isNotEmpty`.
List<DateTime> pendingOccurrences({
  required DateTime? nextDueDate,
  required Recurrence? recurrence,
  required DateTime now,
  DateTime? endDate,
  int? anchorDay,
  int max = maxPendingOccurrences,
}) {
  if (nextDueDate == null || recurrence == null) return const [];

  final today = _dateOnly(now);
  final last = endDate == null ? null : _dateOnly(endDate);
  final out = <DateTime>[];
  var current = nextDueDate;
  while (out.length < max) {
    final day = _dateOnly(current);
    // Due today counts as due — a rent reminder should be actionable on the
    // 1st, not from the 2nd.
    if (day.isAfter(today)) break;
    if (last != null && day.isAfter(last)) break;
    out.add(current);
    current = _step(current, recurrence, anchorDay);
  }
  return out;
}

/// Where the pointer moves once [resolved] has been confirmed or skipped.
///
/// Null means the series is finished — either it ran past its end date, or it
/// never had a recurrence to begin with. A null pointer is what marks a
/// recurring expense as done, so callers should clear `isRecurring` alongside.
DateTime? nextDueAfter(
  DateTime resolved,
  Recurrence? recurrence, {
  DateTime? endDate,
  int? anchorDay,
}) {
  if (recurrence == null) return null;
  final next = _step(resolved, recurrence, anchorDay);
  if (endDate != null && _dateOnly(next).isAfter(_dateOnly(endDate))) {
    return null;
  }
  return next;
}

/// The first due date for a newly-recurring expense anchored at [from].
///
/// Strictly after [from]: the expense being marked recurring is itself the
/// first occurrence and is already logged, so due date #1 is the next one.
/// Null when that first occurrence would already be past [endDate].
DateTime? firstDueDate(
  DateTime from,
  Recurrence? recurrence, {
  DateTime? endDate,
}) => nextDueAfter(
  from,
  recurrence,
  endDate: endDate,
  // The expense's own day is the anchor the whole series is pinned to.
  anchorDay: from.day,
);

import '../../core/db/database.dart';

/// Pure recurring-expense date math (FR-7, logic only — no scheduling, no
/// auto-insert). Drives Sprint 3's remind-and-confirm reminders.

/// Next due date strictly after [from] for a [Recurrence].
///
/// Monthly math clamps to the last valid day when the target month is shorter,
/// so Jan 31 → Feb 28 (or Feb 29 in a leap year), not an overflow into March.
DateTime nextOccurrence(DateTime from, Recurrence r) {
  switch (r) {
    case Recurrence.daily:
      return _addDays(from, 1);
    case Recurrence.weekly:
      return _addDays(from, 7);
    case Recurrence.monthly:
      return _addMonths(from, 1);
  }
}

/// All due dates in the half-open range [start, end), for a recurring series
/// anchored at [anchor]. Occurrences on/after [start] and strictly before [end].
List<DateTime> occurrencesBetween(
  DateTime anchor,
  Recurrence r,
  DateTime start,
  DateTime end,
) {
  final out = <DateTime>[];
  // Walk forward from the anchor until we reach the window, then collect.
  var current = anchor;
  // Fast-forward without collecting while before the window.
  while (current.isBefore(start)) {
    current = nextOccurrence(current, r);
  }
  while (current.isBefore(end)) {
    out.add(current);
    current = nextOccurrence(current, r);
  }
  return out;
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);

DateTime _addMonths(DateTime d, int months) {
  final targetMonthStart = DateTime(d.year, d.month + months, 1);
  final lastDay = _daysInMonth(targetMonthStart.year, targetMonthStart.month);
  final day = d.day < lastDay ? d.day : lastDay; // clamp end-of-month
  return DateTime(targetMonthStart.year, targetMonthStart.month, day,
      d.hour, d.minute, d.second);
}

int _daysInMonth(int year, int month) {
  // Day 0 of next month == last day of this month.
  return DateTime(year, month + 1, 0).day;
}

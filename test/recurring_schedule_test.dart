import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/expenses/recurring_schedule.dart';

void main() {
  group('pendingOccurrences', () {
    test('nothing pending when the expense does not recur', () {
      expect(
        pendingOccurrences(
          nextDueDate: null,
          recurrence: null,
          now: DateTime(2026, 6, 15),
        ),
        isEmpty,
      );
    });

    test('nothing pending while the next due date is still ahead', () {
      expect(
        pendingOccurrences(
          nextDueDate: DateTime(2026, 7, 1),
          recurrence: Recurrence.monthly,
          now: DateTime(2026, 6, 15),
        ),
        isEmpty,
      );
    });

    test('an occurrence due today is pending, not tomorrow-pending', () {
      // Rent due on the 1st must be actionable on the 1st.
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 6, 1),
        recurrence: Recurrence.monthly,
        now: DateTime(2026, 6, 1, 8),
      );
      expect(pending, [DateTime(2026, 6, 1)]);
    });

    test('three missed weeks surface as three separate occurrences', () {
      // The scenario the design was chosen for: a weekly expense ignored for
      // three weeks really was paid three times.
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 6, 1),
        recurrence: Recurrence.weekly,
        now: DateTime(2026, 6, 20),
      );
      expect(pending, [
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 8),
        DateTime(2026, 6, 15),
      ]);
    });

    test('oldest first, so the list can be cleared top-down', () {
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 6, 1),
        recurrence: Recurrence.weekly,
        now: DateTime(2026, 6, 20),
      );
      expect(pending.first.isBefore(pending.last), isTrue);
    });

    test('stops at the end date even when today is well past it', () {
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 6, 1),
        recurrence: Recurrence.monthly,
        endDate: DateTime(2026, 8, 1),
        now: DateTime(2026, 12, 31),
      );
      expect(pending, [
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 1),
        DateTime(2026, 8, 1),
      ]);
    });

    test('an end date on an occurrence includes that occurrence', () {
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 6, 1),
        recurrence: Recurrence.monthly,
        endDate: DateTime(2026, 6, 1),
        now: DateTime(2026, 12, 31),
      );
      expect(pending, [DateTime(2026, 6, 1)]);
    });

    test('caps a long-neglected daily series instead of listing every day', () {
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 1, 1),
        recurrence: Recurrence.daily,
        now: DateTime(2026, 12, 31),
      );
      expect(pending, hasLength(maxPendingOccurrences));
    });

    test('a month-end series clamps for February then springs back', () {
      // The drift this anchoring exists to prevent: chaining nextOccurrence
      // gives Jan 31 → Feb 28 → Mar 28, and rent on the 31st silently becomes
      // rent on the 28th for good.
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 1, 31),
        recurrence: Recurrence.monthly,
        anchorDay: 31,
        now: DateTime(2026, 5, 15),
      );
      expect(pending, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('the 30th survives February too', () {
      final pending = pendingOccurrences(
        nextDueDate: DateTime(2026, 1, 30),
        recurrence: Recurrence.monthly,
        anchorDay: 30,
        now: DateTime(2026, 4, 15),
      );
      expect(pending, [
        DateTime(2026, 1, 30),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 30),
      ]);
    });

    test('weekly and daily ignore the anchor day entirely', () {
      // Their period has no month-length dependency, so passing an anchor
      // must not perturb them.
      expect(
        pendingOccurrences(
          nextDueDate: DateTime(2026, 1, 31),
          recurrence: Recurrence.weekly,
          anchorDay: 31,
          now: DateTime(2026, 2, 15),
        ),
        [DateTime(2026, 1, 31), DateTime(2026, 2, 7), DateTime(2026, 2, 14)],
      );
    });
  });

  group('nextDueAfter', () {
    test('advances by one period', () {
      expect(
        nextDueAfter(DateTime(2026, 6, 1), Recurrence.monthly),
        DateTime(2026, 7, 1),
      );
      expect(
        nextDueAfter(DateTime(2026, 6, 1), Recurrence.weekly),
        DateTime(2026, 6, 8),
      );
    });

    test('returns null once the next one would pass the end date', () {
      expect(
        nextDueAfter(
          DateTime(2026, 8, 1),
          Recurrence.monthly,
          endDate: DateTime(2026, 8, 15),
        ),
        isNull,
      );
    });

    test('an end date exactly on the next occurrence still allows it', () {
      expect(
        nextDueAfter(
          DateTime(2026, 7, 1),
          Recurrence.monthly,
          endDate: DateTime(2026, 8, 1),
        ),
        DateTime(2026, 8, 1),
      );
    });

    test('no recurrence means the series is over', () {
      expect(nextDueAfter(DateTime(2026, 6, 1), null), isNull);
    });

    test('re-anchors a month-end series instead of inheriting the clamp', () {
      expect(
        nextDueAfter(
          DateTime(2026, 2, 28),
          Recurrence.monthly,
          anchorDay: 31,
        ),
        DateTime(2026, 3, 31),
      );
    });
  });

  group('firstDueDate', () {
    test('is the occurrence after the expense itself, never the same day', () {
      // The expense being marked recurring is already logged — it is
      // occurrence #1, so the first *due* one is the next.
      expect(
        firstDueDate(DateTime(2026, 6, 1), Recurrence.monthly),
        DateTime(2026, 7, 1),
      );
    });

    test('is null when the end date lands before the next occurrence', () {
      expect(
        firstDueDate(
          DateTime(2026, 6, 1),
          Recurrence.monthly,
          endDate: DateTime(2026, 6, 20),
        ),
        isNull,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/expenses/recurrence.dart';

void main() {
  group('nextOccurrence', () {
    test('daily / weekly add days', () {
      final d = DateTime(2026, 3, 10);
      expect(nextOccurrence(d, Recurrence.daily), DateTime(2026, 3, 11));
      expect(nextOccurrence(d, Recurrence.weekly), DateTime(2026, 3, 17));
    });

    test('monthly advances one month', () {
      expect(
        nextOccurrence(DateTime(2026, 3, 15), Recurrence.monthly),
        DateTime(2026, 4, 15),
      );
    });

    test('monthly clamps end-of-month: Jan 31 -> Feb 28 (non-leap 2026)', () {
      expect(
        nextOccurrence(DateTime(2026, 1, 31), Recurrence.monthly),
        DateTime(2026, 2, 28),
      );
    });

    test('monthly clamps to Feb 29 in a leap year (2028)', () {
      expect(
        nextOccurrence(DateTime(2028, 1, 31), Recurrence.monthly),
        DateTime(2028, 2, 29),
      );
    });

    test('monthly across year boundary', () {
      expect(
        nextOccurrence(DateTime(2026, 12, 5), Recurrence.monthly),
        DateTime(2027, 1, 5),
      );
    });
  });

  group('occurrencesBetween', () {
    test('daily count in a half-open window', () {
      final dates = occurrencesBetween(
        DateTime(2026, 3, 1),
        Recurrence.daily,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 5), // exclusive
      );
      expect(dates, [
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 3),
        DateTime(2026, 3, 4),
      ]);
    });

    test('weekly across a month boundary, anchor before window', () {
      final dates = occurrencesBetween(
        DateTime(2026, 3, 30), // anchor before window
        Recurrence.weekly,
        DateTime(2026, 4, 1),
        DateTime(2026, 4, 30),
      );
      // Mar30 -> Apr6 -> Apr13 -> Apr20 -> Apr27
      expect(dates, [
        DateTime(2026, 4, 6),
        DateTime(2026, 4, 13),
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 27),
      ]);
    });

    test('empty when window before anchor', () {
      final dates = occurrencesBetween(
        DateTime(2026, 6, 1),
        Recurrence.daily,
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 10),
      );
      expect(dates, isEmpty);
    });
  });
}

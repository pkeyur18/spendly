import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/expenses/quick_add_screen.dart';

/// [tripForDate] is Quick Add's auto-tagging matching rule — pulled out as a
/// free function specifically so it's testable without a widget harness (see
/// its doc comment). The manual-override behavior itself
/// (`_tagManuallySet`) lives on the State class and isn't covered here; this
/// only covers "does this date match this trip".
void main() {
  TagRow trip({
    required int id,
    required DateTime start,
    required DateTime end,
    bool archived = false,
  }) {
    final now = DateTime(2026, 1, 1);
    return TagRow(
      id: id,
      name: 'Trip $id',
      colorValue: 0xFFF59E0B,
      isArchived: archived,
      createdAt: now,
      fxCurrency: null,
      fxRateMicros: null,
      tripStartDate: start,
      tripEndDate: end,
      externalId: null,
    );
  }

  test('matches a date inside the range', () {
    final t = trip(id: 1, start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 10));
    expect(tripForDate([t], DateTime(2026, 3, 5))?.id, 1);
  });

  test('matches both inclusive boundaries', () {
    final t = trip(id: 1, start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 10));
    expect(tripForDate([t], DateTime(2026, 3, 1))?.id, 1);
    expect(tripForDate([t], DateTime(2026, 3, 10))?.id, 1);
  });

  test('ignores time of day — only the calendar date matters', () {
    final t = trip(id: 1, start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 10));
    expect(tripForDate([t], DateTime(2026, 3, 10, 23, 59))?.id, 1);
  });

  test('no match before the start or after the end', () {
    final t = trip(id: 1, start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 10));
    expect(tripForDate([t], DateTime(2026, 2, 28)), isNull);
    expect(tripForDate([t], DateTime(2026, 3, 11)), isNull);
  });

  test('a trip with no date range never matches', () {
    final t = TagRow(
      id: 1,
      name: 'Groceries',
      colorValue: 0xFF6366F1,
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
      fxCurrency: null,
      fxRateMicros: null,
      tripStartDate: null,
      tripEndDate: null,
      externalId: null,
    );
    expect(tripForDate([t], DateTime(2026, 3, 5)), isNull);
  });

  test('empty tag list never matches', () {
    expect(tripForDate(const [], DateTime(2026, 3, 5)), isNull);
  });

  test('the first matching trip wins when ranges are (invalidly) checked anyway', () {
    // The app-level overlap guard prevents this from happening in practice
    // (TagRepository.hasOverlappingDateRange), but the matcher itself should
    // still resolve deterministically rather than throw.
    final a = trip(id: 1, start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 10));
    final b = trip(id: 2, start: DateTime(2026, 3, 5), end: DateTime(2026, 3, 15));
    expect(tripForDate([a, b], DateTime(2026, 3, 7))?.id, 1);
  });
}

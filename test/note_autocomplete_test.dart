import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/expenses/note_autocomplete.dart';

void main() {
  group('matchingNotes', () {
    const ranked = ['Coffee', 'Coworking pass', 'Groceries', 'Gym', 'Gas'];

    test('empty query returns the top-ranked notes as-is', () {
      expect(matchingNotes(ranked, ''), ['Coffee', 'Coworking pass', 'Groceries', 'Gym', 'Gas']);
    });

    test('filters by case-insensitive prefix', () {
      expect(matchingNotes(ranked, 'co'), ['Coffee', 'Coworking pass']);
    });

    test('preserves frequency order among matches', () {
      // "Gym" outranks "Gas" in the input list, so it should stay first.
      expect(matchingNotes(ranked, 'g'), ['Groceries', 'Gym', 'Gas']);
    });

    test('excludes an exact match — nothing left to complete', () {
      expect(matchingNotes(ranked, 'Coffee'), isEmpty);
    });

    test('respects the limit', () {
      expect(matchingNotes(ranked, '', limit: 2), ['Coffee', 'Coworking pass']);
    });

    test('no match returns empty, not an error', () {
      expect(matchingNotes(ranked, 'zzz'), isEmpty);
    });
  });
}

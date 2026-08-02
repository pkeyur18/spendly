import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/currencies.dart';
import 'package:spendly/features/tags/currency_picker_screen.dart';

/// [filterCurrencies] and [sectionCurrencies] are the full-screen picker's
/// pure matching/grouping rules, pulled out specifically so they're
/// unit-testable without a widget harness — see their doc comments.
void main() {
  group('filterCurrencies', () {
    test('empty query returns everything, unfiltered order preserved', () {
      final result = filterCurrencies(travelCurrencies, '');
      expect(result, travelCurrencies);
    });

    test('matches by name, case-insensitive', () {
      final result = filterCurrencies(travelCurrencies, 'thai');
      expect(result.map((c) => c.code), ['THB']);
    });

    test('matches by code, case-insensitive', () {
      final result = filterCurrencies(travelCurrencies, 'usd');
      expect(result.map((c) => c.code), ['USD']);
    });

    test('matches a substring anywhere in the name', () {
      final result = filterCurrencies(travelCurrencies, 'dollar');
      expect(
        result.map((c) => c.code),
        containsAll(['USD', 'SGD', 'AUD', 'CAD', 'HKD', 'NZD']),
      );
    });

    test('trims whitespace before matching', () {
      final result = filterCurrencies(travelCurrencies, '  thb  ');
      expect(result.map((c) => c.code), ['THB']);
    });

    test('no match returns an empty list', () {
      expect(filterCurrencies(travelCurrencies, 'zzz-not-a-currency'), isEmpty);
    });
  });

  group('sectionCurrencies', () {
    test('popular section keeps curated leading order', () {
      final (popular, _) = sectionCurrencies(travelCurrencies);
      expect(popular.first.code, travelCurrencies.first.code);
      expect(popular, orderedEquals(travelCurrencies.take(popular.length)));
    });

    test('A-Z section is sorted by name and excludes every popular entry', () {
      final (popular, alphabetical) = sectionCurrencies(travelCurrencies);
      final names = alphabetical.map((c) => c.name).toList();
      expect(names, equals([...names]..sort()));

      final popularCodes = popular.map((c) => c.code).toSet();
      expect(
        alphabetical.any((c) => popularCodes.contains(c.code)),
        isFalse,
      );
    });

    test('together, both sections cover the full list exactly once', () {
      final (popular, alphabetical) = sectionCurrencies(travelCurrencies);
      final combined = {...popular.map((c) => c.code), ...alphabetical.map((c) => c.code)};
      expect(combined.length, travelCurrencies.length);
    });
  });
}

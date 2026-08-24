import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/ledger/income_screen.dart';

void main() {
  group('groupByMonth', () {
    test('buckets by calendar month, preserving order within a month', () {
      final grouped = groupByMonth<(int, DateTime)>(
        [
          (1, DateTime(2026, 8, 1)),
          (2, DateTime(2026, 8, 14)),
          (3, DateTime(2026, 7, 1)),
        ],
        (e) => e.$2,
      );

      expect(grouped.keys.toSet(), {8, 7});
      expect(grouped[8]!.map((e) => e.$1), [1, 2]);
      expect(grouped[7]!.map((e) => e.$1), [3]);
    });

    test('empty input yields an empty map', () {
      expect(groupByMonth<(int, DateTime)>([], (e) => e.$2), isEmpty);
    });

    test('all entries in one month collapse into a single bucket', () {
      final grouped = groupByMonth<(int, DateTime)>(
        [(1, DateTime(2026, 3, 5)), (2, DateTime(2026, 3, 20))],
        (e) => e.$2,
      );
      expect(grouped.keys, [3]);
      expect(grouped[3], hasLength(2));
    });
  });
}

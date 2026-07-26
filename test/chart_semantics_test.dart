import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/home/dashboard_providers.dart';
import 'package:spendly/features/home/widgets/spend_donut.dart';
import 'package:spendly/features/home/widgets/trend_bars.dart';

CategoryRow _cat(int id, String name) => CategoryRow(
  id: id,
  name: name,
  icon: '🍔',
  colorValue: 0xFF000000,
  sortOrder: 0,
  isArchived: false,
  isDefault: false,
  isIgnoredForBudget: false,
);

void main() {
  group('donutSemanticsLabel', () {
    test('empty slices', () {
      expect(
        donutSemanticsLabel(const [], Money.zero),
        contains('no spending'),
      );
    });

    test('summarizes each slice with its percent', () {
      final slices = <CategorySlice>[
        (_cat(1, 'Food'), Money.fromMinor(40000), 0.6667),
        (_cat(2, 'Transport'), Money.fromMinor(20000), 0.3333),
      ];
      final label = donutSemanticsLabel(slices, Money.fromMinor(60000));
      expect(label, contains('Food 67 percent'));
      expect(label, contains('Transport 33 percent'));
    });

    test('caps at 5 slices', () {
      final slices = <CategorySlice>[
        for (var i = 0; i < 8; i++)
          (_cat(i, 'Cat$i'), Money.fromMinor(100), 0.125),
      ];
      final label = donutSemanticsLabel(slices, Money.fromMinor(800));
      expect(label, isNot(contains('Cat7')));
      expect(label, contains('Cat4'));
    });
  });

  group('trendSemanticsLabel', () {
    test('empty bars', () {
      expect(trendSemanticsLabel(const []), contains('no data'));
    });

    test('flags the current month, no divide-by-zero on flat data', () {
      final bars = <TrendBar>[
        ('Jan', Money.zero, false),
        ('Feb', Money.fromMinor(10000), true),
      ];
      final label = trendSemanticsLabel(bars);
      expect(label, contains('Feb'));
      expect(label, contains('current month'));
      expect(label, isNot(contains('Jan, current month')));
    });
  });
}

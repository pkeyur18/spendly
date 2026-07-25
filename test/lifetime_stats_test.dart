import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/profile/lifetime_stats.dart';

void main() {
  test('empty list yields all-zero stats', () {
    final stats = computeLifetimeStats([]);
    expect(stats.monthsTracked, 0);
    expect(stats.expensesLogged, 0);
    expect(stats.categoriesUsed, 0);
  });

  test('single expense counts as 1 month, 1 expense, 1 category', () {
    final stats = computeLifetimeStats([(DateTime(2026, 7, 1), 3)]);
    expect(stats.monthsTracked, 1);
    expect(stats.expensesLogged, 1);
    expect(stats.categoriesUsed, 1);
  });

  test('multiple expenses across categories and months', () {
    final stats = computeLifetimeStats([
      (DateTime(2026, 7, 1), 1),
      (DateTime(2026, 7, 15), 2),
      (DateTime(2026, 8, 1), 1),
      (DateTime(2026, 8, 2), 3),
    ]);
    expect(stats.monthsTracked, 2); // Jul, Aug 2026
    expect(stats.expensesLogged, 4);
    expect(stats.categoriesUsed, 3); // categories 1, 2, 3
  });

  test('same calendar month in different years counts distinctly', () {
    final stats = computeLifetimeStats([
      (DateTime(2025, 1, 10), 1),
      (DateTime(2026, 1, 10), 1),
    ]);
    expect(stats.monthsTracked, 2); // Jan-2025 and Jan-2026 are different
    expect(stats.expensesLogged, 2);
    expect(stats.categoriesUsed, 1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/expenses/all_transactions_screen.dart';

CategoryRow _category(int id) => CategoryRow(
  id: id,
  name: 'Category $id',
  icon: '🏷️',
  colorValue: 0,
  sortOrder: 0,
  isArchived: false,
  isDefault: false,
  isIgnoredForBudget: false,
);

void main() {
  test('returns all categories when at or under the cap, regardless of expanded', () {
    final categories = List.generate(3, _category);
    expect(visibleCategoryChips(categories, false), categories);
    expect(visibleCategoryChips(categories, true), categories);
  });

  test('collapses to the first max entries when over the cap and not expanded', () {
    final categories = List.generate(5, _category);
    expect(visibleCategoryChips(categories, false), categories.take(3).toList());
  });

  test('returns everything when over the cap and expanded', () {
    final categories = List.generate(5, _category);
    expect(visibleCategoryChips(categories, true), categories);
  });
}

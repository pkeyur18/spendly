import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/expenses/quick_add_screen.dart';

CategoryRow _cat(int id) => CategoryRow(
  id: id,
  name: 'Cat $id',
  icon: '🍔',
  colorValue: 0xFF000000,
  sortOrder: id,
  isArchived: false,
  isDefault: false,
);

void main() {
  final categories = List.generate(10, (i) => _cat(i));

  test('selection within top 7 leaves list unchanged', () {
    final visible = visibleCategoryTiles(categories, 2);
    expect(visible.map((c) => c.id), [0, 1, 2, 3, 4, 5, 6]);
  });

  test('selection past index 6 swaps into last slot', () {
    final visible = visibleCategoryTiles(categories, 8);
    expect(visible.map((c) => c.id), [0, 1, 2, 3, 4, 5, 8]);
  });

  test('null selection returns plain first-N slice', () {
    final visible = visibleCategoryTiles(categories, null);
    expect(visible.map((c) => c.id), [0, 1, 2, 3, 4, 5, 6]);
  });
}

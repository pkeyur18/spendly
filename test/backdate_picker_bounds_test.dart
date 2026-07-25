import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/expenses/quick_add_screen.dart';

void main() {
  test('lastDate caps at today, no future dates', () {
    final now = DateTime(2026, 7, 24, 15, 30);
    final (_, lastDate) = backdatePickerBounds(now);
    expect(lastDate, DateTime(2026, 7, 24));
  });

  test('firstDate is exactly 90 days before now', () {
    final now = DateTime(2026, 7, 24, 15, 30);
    final (firstDate, _) = backdatePickerBounds(now);
    expect(firstDate, now.subtract(const Duration(days: 90)));
    expect(now.difference(firstDate).inDays, 90);
  });
}

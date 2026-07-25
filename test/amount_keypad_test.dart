import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/widgets/amount_keypad.dart';

void main() {
  test('digits replace leading zero, then append', () {
    expect(applyAmountKey('0', '5'), '5');
    expect(applyAmountKey('5', '0'), '50');
  });

  test('single dot allowed, blocks a 3rd decimal', () {
    expect(applyAmountKey('12', '.'), '12.');
    expect(applyAmountKey('12.', '.'), '12.'); // no second dot
    expect(applyAmountKey('12.5', '0'), '12.50');
    expect(applyAmountKey('12.50', '9'), '12.50'); // 3rd decimal blocked
  });

  test('del removes last char, floors at "0"', () {
    expect(applyAmountKey('50', 'del'), '5');
    expect(applyAmountKey('5', 'del'), '0');
    expect(applyAmountKey('0', 'del'), '0');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/widgets/icon_color_picker.dart';

void main() {
  const all = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

  test('selected already within first max stays in place, pinned first', () {
    final result = previewStripItems(all, 'a', max: 4);
    expect(result.items, ['a', 'b', 'c', 'd']);
    expect(result.overflowCount, 4);
  });

  test('selected outside first max gets pinned to front', () {
    final result = previewStripItems(all, 'f', max: 4);
    expect(result.items, ['f', 'a', 'b', 'c']);
    expect(result.overflowCount, 4);
  });

  test('selected not present in list is still pinned first', () {
    final result = previewStripItems(all, 'z', max: 3);
    expect(result.items, ['z', 'a', 'b']);
    expect(result.overflowCount, 6);
  });

  test('max greater than or equal to total items yields zero overflow', () {
    final result = previewStripItems(all, 'a', max: 20);
    expect(result.items, all);
    expect(result.overflowCount, 0);
  });
}

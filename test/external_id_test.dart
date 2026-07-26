import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/external_id.dart';

void main() {
  test('generates a UUID v4-shaped string', () {
    final id = generateExternalId();
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('generates distinct values across calls', () {
    final ids = List.generate(200, (_) => generateExternalId());
    expect(ids.toSet().length, 200);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_repository.dart';

void main() {
  final budget = Money.parse(
    '100',
  ); // ₹100 → 10000 minor. 80% = 8000, 100% = 10000.
  Money m(String s) => Money.parse(s);

  test('crossing 80% only fires [80]', () {
    expect(crossedThresholds(m('70'), m('90'), budget), [80]);
  });

  test('crossing 100% only (already past 80) fires [100]', () {
    expect(crossedThresholds(m('85'), m('105'), budget), [100]);
  });

  test('a single jump past both fires [80, 100]', () {
    expect(crossedThresholds(Money.zero, m('100'), budget), [80, 100]);
  });

  test('exactly hitting the line counts as crossed', () {
    expect(crossedThresholds(m('79'), m('80'), budget), [80]);
    expect(crossedThresholds(m('99'), m('100'), budget), [100]);
  });

  test('no crossing when both sides under 80%', () {
    expect(crossedThresholds(m('10'), m('50'), budget), isEmpty);
  });

  test('already over the line stays quiet (no repeat)', () {
    expect(crossedThresholds(m('90'), m('95'), budget), isEmpty);
    expect(crossedThresholds(m('101'), m('120'), budget), isEmpty);
  });

  test('zero / negative budget never alerts', () {
    expect(crossedThresholds(Money.zero, m('500'), Money.zero), isEmpty);
    expect(
      crossedThresholds(Money.zero, m('500'), Money.fromMinor(-1)),
      isEmpty,
    );
  });

  group('categoryBudgetOverrun', () {
    test('no overall budget set → null (nothing to compare)', () {
      expect(categoryBudgetOverrun(m('100'), null), isNull);
    });

    test('category total under overall → null', () {
      expect(categoryBudgetOverrun(m('80'), m('100')), isNull);
    });

    test('category total exactly equal to overall → null (not an overrun)', () {
      expect(categoryBudgetOverrun(m('100'), m('100')), isNull);
    });

    test('category total over overall → the exceeded amount', () {
      expect(categoryBudgetOverrun(m('120'), m('100')), m('20'));
    });
  });
}

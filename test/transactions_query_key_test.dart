import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/expenses/all_transactions_screen.dart';

/// Regression coverage for a real bug: [transactionsQueryKey]'s search branch
/// used to call `DateTime.now()` fresh on every access, so the returned key
/// (a record, compared by value) differed on virtually every `build()` — not
/// just when the search text changed. `StreamProvider.family` saw a brand-new
/// key each time, tore down whatever query was in flight, and restarted it —
/// so a search never survived long enough between rebuilds to deliver a
/// result. It looked like search was permanently stuck loading.
void main() {
  (DateTime, DateTime) fixedRange() =>
      (DateTime(2026, 6, 1), DateTime(2026, 7, 1));

  test('two calls in the same day produce an identical key', () {
    final first = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: DateTime(2026, 6, 15, 9, 0, 0, 0),
    );
    // A different moment, same calendar day — mirrors two builds seconds
    // apart while the user is mid-keystroke.
    final second = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: DateTime(2026, 6, 15, 9, 0, 3, 500),
    );
    expect(first, second);
  });

  test('the key really does depend on the search text changing', () {
    final now = DateTime(2026, 6, 15, 9);
    final a = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: now,
    );
    final b = transactionsQueryKey(
      searching: true,
      search: 'coffee tea',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: now,
    );
    expect(a, isNot(b));
  });

  test('while searching, the range escapes the visible range entirely', () {
    final key = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: DateTime(2026, 6, 15),
    );
    expect(key.$1, DateTime(2000));
    expect(key.$1, isNot(fixedRange().$1));
    expect(key.$2, isNot(fixedRange().$2));
  });

  test('the search upper bound covers today, not just up to yesterday', () {
    final today = DateTime(2026, 6, 15, 23, 59, 59);
    final key = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: today,
    );
    // watchInRange is half-open [start, end) — the bound has to be tomorrow,
    // not today, or an expense logged today would fall outside it.
    expect(key.$2, DateTime(2026, 6, 16));
  });

  test('not searching uses the visible range verbatim, unmodified', () {
    final key = transactionsQueryKey(
      searching: false,
      search: '',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: DateTime(2026, 6, 15),
    );
    expect((key.$1, key.$2), fixedRange());
  });

  test('crossing midnight between builds is the only thing that changes the '
      'search key, and only the upper bound', () {
    final beforeMidnight = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: DateTime(2026, 6, 15, 23, 59, 59),
    );
    final afterMidnight = transactionsQueryKey(
      searching: true,
      search: 'coffee',
      range: fixedRange(),
      limit: 100,
      categoryKey: '',
      now: DateTime(2026, 6, 16, 0, 0, 1),
    );
    expect(beforeMidnight.$1, afterMidnight.$1); // lower bound never moves
    expect(beforeMidnight.$2, isNot(afterMidnight.$2));
  });
}

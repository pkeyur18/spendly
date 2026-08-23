# Budget Recommendation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recommend next month's overall + per-category budget from the user's own last 6 completed months of spend, shown inline on the budget-setup screen (tap to apply immediately, still editable after) plus an in-app nudge near month-end if next month's budget is still unset.

**Architecture:** Everything is computed live via a pure Dart function composed into a Riverpod provider — no persisted recommendation, no background job (this app has none by design). One new repository method (`earliestExpenseDate`) is the only new query; everything else reuses existing streams (`watchInRange`, `activeCategoriesProvider`, `allTagsProvider`).

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), Drift (SQLite), no new dependencies.

**Spec:** [docs/superpowers/specs/2026-08-23-budget-recommendation-design.md](../specs/2026-08-23-budget-recommendation-design.md)

## Global Constraints

- No new Drift table, no schema migration (schema stays at v9).
- No network, no ML/analytics dependency — pure Dart arithmetic only (offline-first, PRODUCT.md principle #1).
- Money is always `Money` (integer minor units) — never a `double` in any arithmetic.
- Trip-tagged expenses (`Tags.tripStartDate != null`) are excluded from the recommendation's spend history.
- Recommendation window = the 6 calendar months strictly before the current (in-progress) month — never includes partial current-month data.
- Recommendation UI only appears when viewing the real next calendar month (`DateTime(now.year, now.month + 1, 1)`), never on past/current-month views.
- Follow existing file conventions: pure derivation functions + Riverpod providers co-located in one file per feature area (see `dashboard_providers.dart`, `budget_repository.dart`).

---

## Task 1: `ExpenseRepository.earliestExpenseDate()`

**Files:**
- Modify: `lib/features/expenses/expense_repository.dart`
- Test: `test/expense_repository_test.dart`

**Interfaces:**
- Produces: `Future<DateTime?> earliestExpenseDate()` on `ExpenseRepository` — the date of the single oldest expense across all categories, or `null` if there are no expenses at all.

- [ ] **Step 1: Write the failing test**

Add to `test/expense_repository_test.dart` (inside the existing `main()`, alongside the other tests using the shared `db`/`expenses` from `setUp`):

```dart
  test('earliestExpenseDate is null with no expenses, else the oldest date', () async {
    expect(await expenses.earliestExpenseDate(), isNull);

    await expenses.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 10),
    );
    await expenses.add(
      amount: Money.parse('200'),
      categoryId: 1,
      date: DateTime(2026, 1, 5),
    );
    await expenses.add(
      amount: Money.parse('50'),
      categoryId: 2,
      date: DateTime(2026, 2, 1),
    );

    expect(await expenses.earliestExpenseDate(), DateTime(2026, 1, 5));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/expense_repository_test.dart --plain-name "earliestExpenseDate"`
Expected: FAIL — `earliestExpenseDate` isn't defined on `ExpenseRepository`.

- [ ] **Step 3: Write minimal implementation**

Add this method to `ExpenseRepository` in `lib/features/expenses/expense_repository.dart`, right after `totalInRange` (around line 175):

```dart
  /// Date of the single oldest expense across every category, or null when
  /// there are no expenses at all (fresh install). Feeds the recommendation
  /// engine's "how many of the last 6 months are real usage history" check.
  Future<DateTime?> earliestExpenseDate() async {
    final min = _db.expenses.date.min();
    final row = await (_db.selectOnly(
      _db.expenses,
    )..addColumns([min])).getSingle();
    return row.read(min);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/expense_repository_test.dart --plain-name "earliestExpenseDate"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/expenses/expense_repository.dart test/expense_repository_test.dart
git commit -m "feat: add ExpenseRepository.earliestExpenseDate"
```

---

## Task 2: Pure recommendation math

**Files:**
- Create: `lib/features/budgets/budget_recommendation.dart`
- Test: `test/budget_recommendation_test.dart`

**Interfaces:**
- Consumes: `ExpenseRow` (`lib/core/db/database.dart`, fields `categoryId`, `date`, `tagId`, and `.amount` extension from `lib/core/db/row_extensions.dart`), `Money` (`lib/core/money/money.dart`, `Money.zero`, `Money.fromMinor(int)`, `.minor`).
- Produces:
  - `class BudgetRecommendation { final Money amount; final int monthsUsed; }`
  - `List<Map<int, Money>> monthlyCategoryTotals(List<ExpenseRow> expenses, Set<int> tripTagIds, DateTime now)` — 6 maps, oldest→newest.
  - `int monthsUsedInWindow(DateTime? earliestExpenseMonth, DateTime now)`
  - `Money? recommendCategoryBudget(List<Money> monthlyTotals)`

- [ ] **Step 1: Write the failing tests**

Create `test/budget_recommendation_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/budgets/budget_recommendation.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/tags/tag_repository.dart';

void main() {
  group('recommendCategoryBudget', () {
    test('null when every month is zero', () {
      expect(
        recommendCategoryBudget(List.filled(6, Money.zero)),
        isNull,
      );
    });

    test('flat history rounds to itself at a ₹50 boundary', () {
      final totals = List.filled(6, Money.fromMinor(300000)); // ₹3000 x6
      expect(recommendCategoryBudget(totals), Money.fromMinor(300000));
    });

    test('weights recent months higher than older ones', () {
      // Oldest -> newest: 1000, 1000, 1000, 1000, 1000, 4000 (all minor x100).
      final totals = [
        for (var i = 0; i < 5; i++) Money.fromMinor(100000),
        Money.fromMinor(400000),
      ];
      final result = recommendCategoryBudget(totals)!;
      // Plain average would be 1500; weighting the newest (heaviest weight)
      // month higher pulls the result above that.
      expect(result.minor, greaterThan(Money.fromMinor(150000).minor));
    });

    test('drops a single month exceeding 1.75x the median (>=4 months only)', () {
      // Median of [1000,1000,1000,1000,1000] is 1000; 5000 > 1.75x1000, dropped.
      final totals = [
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(500000),
      ];
      final result = recommendCategoryBudget(totals)!;
      // With the outlier dropped, every remaining month is ₹1000 flat.
      expect(result, Money.fromMinor(100000));
    });

    test('outlier guard is skipped with fewer than 4 months of data', () {
      // A caller trims the fixed 6-slot window down to just the months that
      // are real history (see monthsUsedInWindow) before calling this
      // function — so it must also behave correctly on short lists, not
      // just the full 6.
      final totals = [
        Money.fromMinor(100000),
        Money.fromMinor(100000),
        Money.fromMinor(500000), // would be dropped at >=4 months; kept here
      ];
      final result = recommendCategoryBudget(totals)!;
      // Weights 1,2,3, nothing dropped: (100000*1 + 100000*2 + 500000*3) / 6
      // = 300000 exactly, already on a ₹50 boundary.
      expect(result, Money.fromMinor(300000));
    });
  });

  group('monthsUsedInWindow', () {
    final now = DateTime(2026, 8, 15);

    test('null earliest date -> 0 months used', () {
      expect(monthsUsedInWindow(null, now), 0);
    });

    test('earliest expense 3 months ago -> 3 months used', () {
      expect(monthsUsedInWindow(DateTime(2026, 5, 20), now), 3);
    });

    test('earliest expense before the whole window -> full 6 months used', () {
      expect(monthsUsedInWindow(DateTime(2024, 1, 1), now), 6);
    });
  });

  group('monthlyCategoryTotals', () {
    late AppDatabase db;
    late ExpenseRepository expenses;
    late TagRepository tags;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      expenses = ExpenseRepository(db);
      tags = TagRepository(db);
    });
    tearDown(() => db.close());

    test('buckets by month and category, oldest to newest', () async {
      final now = DateTime(2026, 8, 15);
      await expenses.add(
        amount: Money.parse('1000'),
        categoryId: 1,
        date: DateTime(2026, 7, 10), // 1 month back -> last bucket
      );
      await expenses.add(
        amount: Money.parse('2000'),
        categoryId: 1,
        date: DateTime(2026, 2, 10), // 6 months back -> first bucket
      );
      final rows = await expenses.watchInRange(
        DateTime(2026, 2, 1),
        DateTime(2026, 8, 1),
      ).first;

      final buckets = monthlyCategoryTotals(rows, {}, now);
      expect(buckets.length, 6);
      expect(buckets.first[1], Money.parse('2000')); // Feb, oldest
      expect(buckets.last[1], Money.parse('1000')); // Jul, newest
    });

    test('excludes trip-tagged expenses', () async {
      final now = DateTime(2026, 8, 15);
      final tripTagId = await tags.create(
        name: 'Bali',
        colorValue: 0xFF000000,
        tripStartDate: DateTime(2026, 7, 1),
        tripEndDate: DateTime(2026, 7, 5),
      );
      await expenses.add(
        amount: Money.parse('5000'),
        categoryId: 1,
        date: DateTime(2026, 7, 2),
        tagId: tripTagId,
      );
      await expenses.add(
        amount: Money.parse('500'),
        categoryId: 1,
        date: DateTime(2026, 7, 3),
      );
      final rows = await expenses.watchInRange(
        DateTime(2026, 2, 1),
        DateTime(2026, 8, 1),
      ).first;

      final buckets = monthlyCategoryTotals(rows, {tripTagId}, now);
      expect(buckets.last[1], Money.parse('500')); // trip expense excluded
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/budget_recommendation_test.dart`
Expected: FAIL — `package:spendly/features/budgets/budget_recommendation.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/budgets/budget_recommendation.dart`:

```dart
import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';

/// One category's recommended next-month budget, and how many of the last 6
/// calendar months actually fall within the user's usage history (the rest
/// predate their first-ever expense, so aren't real zero-spend data).
class BudgetRecommendation {
  const BudgetRecommendation({required this.amount, required this.monthsUsed});
  final Money amount;
  final int monthsUsed;
}

/// Buckets [expenses] into the 6 calendar months immediately before [now]'s
/// month (oldest -> newest; [now]'s own in-progress month is never
/// included), per category, with trip-tagged expenses excluded. [expenses]
/// is expected to already be scoped to that 6-month window - this function
/// only buckets and filters, it doesn't fetch.
List<Map<int, Money>> monthlyCategoryTotals(
  List<ExpenseRow> expenses,
  Set<int> tripTagIds,
  DateTime now,
) {
  final counted = expenses.where(
    (e) => e.tagId == null || !tripTagIds.contains(e.tagId),
  );
  final buckets = <Map<int, Money>>[];
  for (var i = 6; i >= 1; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    final totals = <int, Money>{};
    for (final e in counted) {
      if (e.date.year == m.year && e.date.month == m.month) {
        totals[e.categoryId] = (totals[e.categoryId] ?? Money.zero) + e.amount;
      }
    }
    buckets.add(totals);
  }
  return buckets;
}

/// How many of the 6 window months fall on/after [earliestExpenseMonth] -
/// the rest predate the user's first-ever expense. 0 when there's no
/// expense history at all.
int monthsUsedInWindow(DateTime? earliestExpenseMonth, DateTime now) {
  if (earliestExpenseMonth == null) return 0;
  final earliestMonthStart = DateTime(
    earliestExpenseMonth.year,
    earliestExpenseMonth.month,
    1,
  );
  var count = 0;
  for (var i = 6; i >= 1; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    if (!m.isBefore(earliestMonthStart)) count++;
  }
  return count;
}

/// Recommended next-month budget for one category, from its monthly totals
/// (oldest -> newest, already trimmed to real history by the caller — see
/// `budgetRecommendationsProvider`; a month with no spend is a real 0, not
/// missing). Weighted average favouring recent months; the single month
/// exceeding 1.75x the median is dropped first (only once there are >= 4
/// months, so a small sample can't be gutted by outlier removal). Rounded to
/// the nearest ₹50. Null when every month is zero (no history at all).
Money? recommendCategoryBudget(List<Money> monthlyTotals) {
  if (monthlyTotals.every((m) => m.minor == 0)) return null;

  var totals = monthlyTotals;
  if (totals.length >= 4) {
    final sorted = [...totals]..sort((a, b) => a.minor.compareTo(b.minor));
    final median = sorted[sorted.length ~/ 2];
    Money? worstOutlier;
    if (median.minor > 0) {
      for (final m in totals) {
        if (m.minor > median.minor * 175 ~/ 100) {
          if (worstOutlier == null || m.minor > worstOutlier.minor) {
            worstOutlier = m;
          }
        }
      }
    }
    if (worstOutlier != null) {
      totals = [...totals]..removeAt(totals.indexOf(worstOutlier));
    }
  }

  var weightedSum = 0;
  var weightTotal = 0;
  for (var i = 0; i < totals.length; i++) {
    final weight = i + 1; // oldest = 1 .. newest = totals.length
    weightedSum += totals[i].minor * weight;
    weightTotal += weight;
  }
  final average = weightedSum ~/ weightTotal;
  const roundToMinor = 5000; // nearest ₹50
  final rounded =
      ((average + roundToMinor ~/ 2) ~/ roundToMinor) * roundToMinor;
  return Money.fromMinor(rounded);
}
```

Check `lib/core/db/row_extensions.dart` for the exact name of the `Money` accessor on `ExpenseRow` before finalizing the import above (it's used as `e.amount` elsewhere, e.g. `dashboard_providers.dart:19` and `report_model.dart:70`) — reuse that extension, don't add a new one.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/budget_recommendation_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/budgets/budget_recommendation.dart test/budget_recommendation_test.dart
git commit -m "feat: add pure budget recommendation math"
```

---

## Task 3: Compose per-category + overall recommendations, then wire Riverpod

**Files:**
- Modify: `lib/features/budgets/budget_recommendation.dart` (append the compose function, then the providers)
- Modify: `test/budget_recommendation_test.dart` (append to the file from Task 2)

**Interfaces:**
- Consumes: `CategoryRow` (`lib/core/db/database.dart`), `monthlyCategoryTotals`/`monthsUsedInWindow`/`recommendCategoryBudget`/`BudgetRecommendation` (Task 2), `expenseRepositoryProvider`, `activeCategoriesProvider`, `allTagsProvider`.
- Produces:
  - `(Map<int, BudgetRecommendation>, Money?) buildBudgetRecommendations({required List<CategoryRow> categories, required List<Map<int, Money>> buckets, required int monthsUsed})` — pure, no DB/Riverpod. `.$1` keyed by `categoryId` (only non-ignored-for-budget categories with real history), `.$2` is the sum of `.$1`'s amounts or `null` when `.$1` is empty.
  - `final budgetRecommendationsProvider = Provider<(Map<int, BudgetRecommendation>, Money?)>(...)` — thin Riverpod wiring around the above, deliberately left without its own test (same convention as `trendProvider` in `dashboard_providers.dart:103-106`, which wires up `trendBuckets` without a separate provider-level test — the pure function underneath is what's tested).

A plain `Provider` combining several `StreamProvider`s via `.value` is timing-sensitive to read synchronously right after a DB write in a test (Drift's `.watch()` needs a tick to emit) — this codebase has no precedent for testing that combination directly, so don't add one. Keep the actual decision logic in the pure `buildBudgetRecommendations`, tested against real repository data exactly like `report_model_test.dart` tests `buildReport`.

- [ ] **Step 1: Write the failing tests**

Append to `test/budget_recommendation_test.dart` (new imports at the top, new `group` in `main()`):

```dart
import 'package:spendly/features/categories/category_repository.dart';
```

```dart
  group('buildBudgetRecommendations', () {
    late AppDatabase db;
    late ExpenseRepository expenses;
    late CategoryRepository categories;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      expenses = ExpenseRepository(db);
      categories = CategoryRepository(db);
    });
    tearDown(() => db.close());

    test('no expenses at all -> empty recommendations, null overall', () async {
      final cats = await categories.watchAll().first;
      final buckets = monthlyCategoryTotals(const [], {}, DateTime.now());
      final (perCategory, overall) = buildBudgetRecommendations(
        categories: cats,
        buckets: buckets,
        monthsUsed: 0,
      );
      expect(perCategory, isEmpty);
      expect(overall, isNull);
    });

    test('recommends per category and sums to the overall figure', () async {
      final now = DateTime.now();
      for (var i = 1; i <= 6; i++) {
        await expenses.add(
          amount: Money.fromMinor(300000), // ₹3000 flat every month
          categoryId: 1,
          date: DateTime(now.year, now.month - i, 10),
        );
      }
      final rows = await expenses.watchInRange(
        DateTime(now.year, now.month - 6, 1),
        DateTime(now.year, now.month, 1),
      ).first;
      final cats = await categories.watchAll().first;
      final buckets = monthlyCategoryTotals(rows, {}, now);

      final (perCategory, overall) = buildBudgetRecommendations(
        categories: cats,
        buckets: buckets,
        monthsUsed: 6,
      );
      expect(perCategory[1]?.amount, Money.fromMinor(300000));
      expect(overall, Money.fromMinor(300000));
    });

    test('ignored-for-budget categories are excluded from both maps', () async {
      await categories.setIgnoredForBudget(1, true);
      final now = DateTime.now();
      for (var i = 1; i <= 6; i++) {
        await expenses.add(
          amount: Money.fromMinor(300000),
          categoryId: 1,
          date: DateTime(now.year, now.month - i, 10),
        );
      }
      final rows = await expenses.watchInRange(
        DateTime(now.year, now.month - 6, 1),
        DateTime(now.year, now.month, 1),
      ).first;
      final cats = await categories.watchAll().first;
      final buckets = monthlyCategoryTotals(rows, {}, now);

      final (perCategory, overall) = buildBudgetRecommendations(
        categories: cats,
        buckets: buckets,
        monthsUsed: 6,
      );
      expect(perCategory.containsKey(1), isFalse);
      expect(overall, isNull);
    });

    test(
      'new user with 2 months of history recommends from those 2 months '
      'only, not diluted by pre-history padding',
      () async {
        final now = DateTime.now();
        // Only the most recent 2 of the 6 window months have any spend — the
        // other 4 predate this user's first-ever expense.
        await expenses.add(
          amount: Money.fromMinor(200000), // ₹2000
          categoryId: 1,
          date: DateTime(now.year, now.month - 2, 10),
        );
        await expenses.add(
          amount: Money.fromMinor(200000),
          categoryId: 1,
          date: DateTime(now.year, now.month - 1, 10),
        );
        final rows = await expenses.watchInRange(
          DateTime(now.year, now.month - 6, 1),
          DateTime(now.year, now.month, 1),
        ).first;
        final cats = await categories.watchAll().first;
        final buckets = monthlyCategoryTotals(rows, {}, now);

        final (perCategory, _) = buildBudgetRecommendations(
          categories: cats,
          buckets: buckets,
          monthsUsed: 2, // real value of monthsUsedInWindow(earliest, now) here
        );
        // If the 4 pre-history months were wrongly averaged in as real
        // zero-spend months, this would land well under ₹2000.
        expect(perCategory[1]?.amount, Money.fromMinor(200000));
        expect(perCategory[1]?.monthsUsed, 2);
      },
    );
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/budget_recommendation_test.dart --plain-name "buildBudgetRecommendations"`
Expected: FAIL — `buildBudgetRecommendations` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/features/budgets/budget_recommendation.dart`:

```dart
/// Composes the per-category + overall recommendations from already-fetched
/// data: [categories] (active ones; ignored-for-budget ones are excluded
/// here), [buckets] (6 months of per-category totals, oldest -> newest, from
/// [monthlyCategoryTotals]), and [monthsUsed] (from [monthsUsedInWindow]).
/// Pure — no DB, no Riverpod — unit-tested at the function level like
/// `buildReport` in `report_model.dart`.
(Map<int, BudgetRecommendation>, Money?) buildBudgetRecommendations({
  required List<CategoryRow> categories,
  required List<Map<int, Money>> buckets,
  required int monthsUsed,
}) {
  // The leading slots before the user's first-ever expense are padding, not
  // real zero-spend months, and must never be averaged in as if they were.
  final realBuckets = buckets.sublist(6 - monthsUsed);

  final perCategory = <int, BudgetRecommendation>{};
  for (final cat in categories) {
    if (cat.isIgnoredForBudget) continue;
    final monthlyTotals = [
      for (final b in realBuckets) b[cat.id] ?? Money.zero,
    ];
    final amount = recommendCategoryBudget(monthlyTotals);
    if (amount != null) {
      perCategory[cat.id] = BudgetRecommendation(
        amount: amount,
        monthsUsed: monthsUsed,
      );
    }
  }
  final overall = perCategory.isEmpty
      ? null
      : perCategory.values.fold(Money.zero, (a, r) => a + r.amount);
  return (perCategory, overall);
}
```

Add these imports at the top of `lib/features/budgets/budget_recommendation.dart`, then the providers below the compose function:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';
import '../tags/tag_repository.dart';
```

```dart
final _last6CompletedMonthsExpensesProvider = StreamProvider<List<ExpenseRow>>(
  (ref) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 6, 1);
    final end = DateTime(now.year, now.month, 1);
    return ref.watch(expenseRepositoryProvider).watchInRange(start, end);
  },
);

final _earliestExpenseMonthProvider = FutureProvider<DateTime?>(
  (ref) => ref.watch(expenseRepositoryProvider).earliestExpenseDate(),
);

/// Recommended next-month budgets — thin Riverpod wiring around
/// [buildBudgetRecommendations]; see that function for the actual logic and
/// its tests.
final budgetRecommendationsProvider =
    Provider<(Map<int, BudgetRecommendation>, Money?)>((ref) {
      final expenses =
          ref.watch(_last6CompletedMonthsExpensesProvider).value ?? const [];
      final tags = ref.watch(allTagsProvider).value ?? const [];
      final categories = ref.watch(activeCategoriesProvider).value ?? const [];
      final earliest = ref.watch(_earliestExpenseMonthProvider).value;
      final now = DateTime.now();

      final tripTagIds = {
        for (final t in tags)
          if (t.tripStartDate != null) t.id,
      };
      return buildBudgetRecommendations(
        categories: categories,
        buckets: monthlyCategoryTotals(expenses, tripTagIds, now),
        monthsUsed: monthsUsedInWindow(earliest, now),
      );
    });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/budget_recommendation_test.dart`
Expected: PASS (all groups: `recommendCategoryBudget`, `monthsUsedInWindow`, `monthlyCategoryTotals`, `buildBudgetRecommendations`)

- [ ] **Step 5: Commit**

```bash
git add lib/features/budgets/budget_recommendation.dart test/budget_recommendation_test.dart
git commit -m "feat: compose budget recommendations and wire a Riverpod provider"
```

---

## Task 4: In-app month-end nudge

**Files:**
- Modify: `lib/core/db/providers.dart` (new settings key)
- Create: `lib/features/budgets/budget_nudge_provider.dart`
- Test: `test/budget_nudge_provider_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository` (`lib/core/db/providers.dart`), `overallBudgetForMonthProvider`/`monthKeyFor` (`lib/features/budgets/budget_repository.dart`, `lib/core/db/database.dart`), `appNavigatorKey` (`lib/core/notify/notifications.dart`).
- Produces: `bool shouldShowBudgetNudge({required DateTime now, required bool nextMonthBudgetSet, required String? lastNudgedMonthKey})`, `final budgetNudgeCheckProvider = FutureProvider<void>(...)`.

- [ ] **Step 1: Write the failing test**

Create `test/budget_nudge_provider_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/features/budgets/budget_nudge_provider.dart';
import 'package:spendly/features/budgets/budget_repository.dart';
import 'package:spendly/core/money/money.dart';

void main() {
  group('shouldShowBudgetNudge (pure predicate)', () {
    test('false outside the last 3 days of the month', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 20),
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: null,
        ),
        isFalse,
      );
    });

    test('false when next month budget is already set', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 30),
          nextMonthBudgetSet: true,
          lastNudgedMonthKey: null,
        ),
        isFalse,
      );
    });

    test('false when already nudged this month', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 30),
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: '2026-08',
        ),
        isFalse,
      );
    });

    test('true in the last 3 days, unset, not yet nudged', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 8, 30), // August has 31 days
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: '2026-07',
        ),
        isTrue,
      );
    });

    test('handles short months correctly (Feb 26/27/28)', () {
      expect(
        shouldShowBudgetNudge(
          now: DateTime(2026, 2, 26), // Feb 2026 has 28 days
          nextMonthBudgetSet: false,
          lastNudgedMonthKey: null,
        ),
        isTrue,
      );
    });
  });

  group('budgetNudgeCheckProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
    });
    tearDown(() {
      container.dispose();
      db.close();
    });

    test('does not mark the gate outside the nudge window', () async {
      await container.read(budgetNudgeCheckProvider.future);
      final settings = container.read(settingsRepositoryProvider);
      expect(
        await settings.get(SettingsRepository.lastBudgetNudgeMonthKey),
        isNull,
      );
    });
  });
}
```

Note: the last test only exercises the "not in window" branch deterministically (it runs whatever today's real date is, so it can only safely assert the negative case without controlling `DateTime.now()`). This matches the project's existing pattern in `monthly_recap_check_provider_test.dart`, which also drives its provider off the real clock.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/budget_nudge_provider_test.dart`
Expected: FAIL — `lib/features/budgets/budget_nudge_provider.dart` doesn't exist, `SettingsRepository.lastBudgetNudgeMonthKey` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

In `lib/core/db/providers.dart`, add the new key next to `lastRecapMonthKey` (around line 44):

```dart
  // Budget recommendation nudge (auto-show-once gate) — the monthKey of the
  // month we last showed the "set next month's budget" nudge for.
  static const lastBudgetNudgeMonthKey = 'last_budget_nudge_month';
```

Create `lib/features/budgets/budget_nudge_provider.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart' show monthKeyFor;
import '../../core/db/providers.dart';
import '../../core/notify/notifications.dart' show appNavigatorKey;
import '../../core/theme/app_theme.dart';
import 'budget_repository.dart';
import 'budget_setup_screen.dart';

/// Whether to show the "set next month's budget" nudge right now: only in
/// the last 3 calendar days of the month, only if next month's overall
/// budget is still unset, and only once per month (gated by
/// [lastNudgedMonthKey], the monthKey it last fired for).
bool shouldShowBudgetNudge({
  required DateTime now,
  required bool nextMonthBudgetSet,
  required String? lastNudgedMonthKey,
}) {
  if (nextMonthBudgetSet) return false;
  if (lastNudgedMonthKey == monthKeyFor(now)) return false;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  return now.day > daysInMonth - 3;
}

/// Runs the once-per-calendar-month "nudge to set next month's budget" check
/// on app launch/resume — same shape as `monthlyRecapCheckProvider`
/// (`features/recap/recap_providers.dart`), invalidated on resume in
/// `app.dart`'s lifecycle observer. Shows a dialog (not a real OS
/// notification - see the design spec's "Nudge type" decision) since this
/// app has no background execution to fire a truly conditional system
/// notification.
final budgetNudgeCheckProvider = FutureProvider<void>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final now = DateTime.now();
  final currentKey = monthKeyFor(now);
  final lastNudged = await settings.get(SettingsRepository.lastBudgetNudgeMonthKey);

  final nextMonth = DateTime(now.year, now.month + 1, 1);
  final nextMonthBudget = await ref
      .watch(budgetRepositoryProvider)
      .watchOverallBudget(nextMonth)
      .first;

  if (!shouldShowBudgetNudge(
    now: now,
    nextMonthBudgetSet: nextMonthBudget != null,
    lastNudgedMonthKey: lastNudged,
  )) {
    return;
  }

  await settings.set(SettingsRepository.lastBudgetNudgeMonthKey, currentKey);

  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Theme(
      data: AppTheme.boldDialogActions(dialogContext),
      child: AlertDialog(
        title: const Text('Set next month\'s budget?'),
        content: const Text(
          'The month is almost over and next month doesn\'t have a budget yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(dialogContext).push(
                MaterialPageRoute(
                  builder: (_) => BudgetSetupScreen(initialMonth: nextMonth),
                ),
              );
            },
            child: const Text('Set it now'),
          ),
        ],
      ),
    ),
  );
});
```

This references `BudgetSetupScreen(initialMonth: nextMonth)`, added in Task 6 — until that task lands, this file won't compile. That's expected; Task 6 completes the cycle. (If executing tasks out of order via subagent-driven-development, land Task 6 before or alongside this one.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/budget_nudge_provider_test.dart`
Expected: PASS for `shouldShowBudgetNudge` group unconditionally; the `budgetNudgeCheckProvider` group's one test passes whenever today isn't in the real last-3-days-of-month window, and requires Task 6's `BudgetSetupScreen(initialMonth: ...)` to exist to compile at all.

- [ ] **Step 5: Commit**

```bash
git add lib/core/db/providers.dart lib/features/budgets/budget_nudge_provider.dart test/budget_nudge_provider_test.dart
git commit -m "feat: add in-app nudge to set next month's budget"
```

---

## Task 5: `BudgetSetupScreen` — deep-linkable initial month + suggestion UI

**Files:**
- Modify: `lib/features/budgets/budget_setup_screen.dart`

**Interfaces:**
- Consumes: `budgetRecommendationsProvider` (Task 3).
- Produces: `BudgetSetupScreen({super.key, DateTime? initialMonth})` — `initialMonth` defaults to the current month exactly as today, preserving every existing call site (`home_screen.dart:219`, `category_manager_screen.dart:50`) unchanged.

- [ ] **Step 1: Add the `initialMonth` constructor param**

In `lib/features/budgets/budget_setup_screen.dart`, change:

```dart
class BudgetSetupScreen extends ConsumerStatefulWidget {
  const BudgetSetupScreen({super.key});

  @override
  ConsumerState<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}
```

to:

```dart
class BudgetSetupScreen extends ConsumerStatefulWidget {
  const BudgetSetupScreen({super.key, this.initialMonth});

  /// Month to open on. Null (the default, every existing call site) opens on
  /// the current calendar month, same as before this param existed.
  final DateTime? initialMonth;

  @override
  ConsumerState<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}
```

and change the state's field initializer from:

```dart
class _BudgetSetupScreenState extends ConsumerState<BudgetSetupScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
```

to:

```dart
class _BudgetSetupScreenState extends ConsumerState<BudgetSetupScreen> {
  late DateTime _month = widget.initialMonth != null
      ? DateTime(widget.initialMonth!.year, widget.initialMonth!.month, 1)
      : DateTime(DateTime.now().year, DateTime.now().month, 1);
```

- [ ] **Step 2: Manually verify existing call sites are unaffected**

Run: `flutter analyze lib/features/home/home_screen.dart lib/features/categories/category_manager_screen.dart lib/features/budgets/budget_setup_screen.dart`
Expected: no errors — both existing call sites construct `BudgetSetupScreen()` with no arguments, which still works since `initialMonth` is optional.

- [ ] **Step 3: Wire the recommendation provider and add a "next real month" check**

Add this private method on `_BudgetSetupScreenState`, right after `_stepMonth` (around line 33):

```dart
  bool _isNextRealMonth() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1, 1);
    return _month.year == next.year && _month.month == next.month;
  }
```

In `build()`, right after `final monthKey = monthKeyFor(_month);` (line 37), add:

```dart
    final isNextRealMonth = _isNextRealMonth();
    final (recommendedByCategory, recommendedOverall) = isNextRealMonth
        ? ref.watch(budgetRecommendationsProvider)
        : (const <int, BudgetRecommendation>{}, null);
```

Add the import at the top of the file:

```dart
import 'budget_recommendation.dart';
```

- [ ] **Step 4: Show the overall suggestion when unset**

In `_BudgetCard`, add two optional fields for the suggestion (right after the existing `onToggleIgnored` field, around line 392):

```dart
  /// Null = no suggestion to show. Non-null shows a "Suggested ₹X" line
  /// that applies the amount immediately on tap, without opening the
  /// amount-entry sheet.
  final Money? suggestion;
  final VoidCallback? onApplySuggestion;
```

and add them to the constructor:

```dart
  const _BudgetCard({
    required this.title,
    required this.spent,
    required this.budget,
    required this.onTap,
    this.onDelete,
    this.isIgnored,
    this.onToggleIgnored,
    this.suggestion,
    this.onApplySuggestion,
  });
```

In `_BudgetCard.build()`, right after the closing of the `if (isIgnored != null) ...` block and before the `const SizedBox(height: 10),` that precedes the progress bar (around line 468), add:

```dart
            if (!has && suggestion != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: onApplySuggestion,
                child: Text(
                  'Suggested ${suggestion!.format(locale: 'en_IN')} · tap to use',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
```

Update the overall-budget `_BudgetCard` construction in the main `body`'s `children` list to pass the suggestion:

```dart
          _BudgetCard(
            title: 'Overall monthly budget',
            spent: monthTotal,
            budget: effectiveOverall,
            onTap: () => _editOverall(context, ref, overall),
            suggestion: recommendedOverall,
            onApplySuggestion: recommendedOverall == null
                ? null
                : () => ref
                    .read(budgetRepositoryProvider)
                    .setOverall(_month, recommendedOverall),
          ),
```

- [ ] **Step 5: Add a suggested-categories section for not-yet-budgeted categories**

Immediately before the existing `_AddBudgetButton(...)` widget in `body`'s `children` (around line 155), add:

```dart
          if (isNextRealMonth)
            for (final c in budgetable)
              if (recommendedByCategory[c.id] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SuggestedCategoryRow(
                    category: c,
                    recommendation: recommendedByCategory[c.id]!,
                    onApply: () => ref
                        .read(budgetRepositoryProvider)
                        .setForCategory(
                          _month,
                          c.id,
                          recommendedByCategory[c.id]!.amount,
                        ),
                  ),
                ),
```

Add the new `_SuggestedCategoryRow` widget at the bottom of the file, after `_AddBudgetButton`:

```dart
/// One not-yet-budgeted category's suggested next-month amount — tapping
/// applies it immediately via [onApply]; the category then re-renders as a
/// normal `_BudgetCard` (still editable) on the next build, since it now has
/// a budget row.
class _SuggestedCategoryRow extends StatelessWidget {
  const _SuggestedCategoryRow({
    required this.category,
    required this.recommendation,
    required this.onApply,
  });

  final CategoryRow category;
  final BudgetRecommendation recommendation;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onApply,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${category.icon} ${category.name}',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              recommendation.monthsUsed < 6
                  ? 'Suggested ${recommendation.amount.format(locale: 'en_IN')} (${recommendation.monthsUsed}mo)'
                  : 'Suggested ${recommendation.amount.format(locale: 'en_IN')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Check `withValues(alpha:)` is the right API on the project's Flutter SDK version (it replaced the deprecated `withOpacity` in recent Flutter) by grepping for an existing use, e.g. `grep -rn "withValues(alpha" lib/` — if the codebase still uses `withOpacity`, match that instead.

- [ ] **Step 6: Manually verify in the running app**

This project's convention is manual verification, not widget-pumped tests, for screens built on Drift streams (see the project's standing note: Drift streams + fl_chart never settle with `pumpAndSettle`). Do NOT run `flutter run` yourself — hand off to the user to check:
1. Open Budget Setup on the current month → no suggestions shown anywhere.
2. Step to next month with no budget set yet → overall card shows "Suggested ₹X · tap to use"; any category with spend history but no budget yet shows a suggestion row above "+ Set budget for a category".
3. Tap a suggestion → it becomes a normal budget card immediately, still editable via the normal tap-to-edit flow.
4. A category with `isIgnoredForBudget = true` never shows a suggestion.

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze`
Expected: no new errors/warnings introduced by this task's changes.

- [ ] **Step 8: Commit**

```bash
git add lib/features/budgets/budget_setup_screen.dart
git commit -m "feat: show tap-to-apply budget suggestions on the setup screen"
```

---

## Task 6: Wire the nudge into `app.dart`

**Files:**
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `budgetNudgeCheckProvider` (Task 4).

- [ ] **Step 1: Add the import**

```dart
import 'features/budgets/budget_nudge_provider.dart';
```

- [ ] **Step 2: Fire the check on cold start / rebuild**

In `build()`, right after the existing:

```dart
    ref.watch(
      monthlyRecapCheckProvider,
    ); // fires the once-per-month recap check
```

add:

```dart
    ref.watch(
      budgetNudgeCheckProvider,
    ); // fires the once-per-month budget nudge check
```

- [ ] **Step 3: Re-check on resume**

In `didChangeAppLifecycleState`, right after the existing:

```dart
      ref.invalidate(monthlyRecapCheckProvider);
```

add:

```dart
      ref.invalidate(budgetNudgeCheckProvider);
```

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS — every existing test still passes, plus all tests added in Tasks 1-4.

- [ ] **Step 5: Run static analysis**

Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/app.dart
git commit -m "feat: fire the budget nudge check on launch and resume"
```

---

## Post-implementation deliverable (do this after Task 6, not before)

The user has asked for an impact/risk assessment and a regression/manual test list once implementation is done. Do not write this until all 6 tasks are committed and `flutter test` + `flutter analyze` are clean. It should cover: which existing screens/providers this touches (`BudgetSetupScreen`, `app.dart` lifecycle, `expense_repository.dart`), what could regress (existing budget CRUD flows, app cold-start/resume timing), and what needs manual verification (the 4 manual-check items in Task 5 Step 6, plus nudge dialog behavior near real month-end if that's reachable in testing, or by temporarily faking `DateTime.now()` inputs to `shouldShowBudgetNudge` as already covered by its unit tests).

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/home/dashboard_providers.dart';
import 'package:spendly/features/widgets/widget_snapshot.dart';

void main() {
  late AppDatabase db;
  late List<CategoryRow> cats;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cats = await CategoryRepository(db).watchActive().first; // 8 seeded defaults
  });
  tearDown(() => db.close());

  final now = DateTime(2026, 7, 23);
  List<TrendBar> flatTrend() => trendBuckets(const [], 6, now);

  test('today and month totals stay distinct', () {
    final snap = buildWidgetSnapshot(
      todayTotal: Money.parse('350'),
      monthTotal: Money.parse('24350'),
      budget: null,
      trend: flatTrend(),
      quickAddCategories: cats,
      now: now,
    );
    expect(snap[WidgetKeys.todayTotal], contains('350'));
    expect(snap[WidgetKeys.monthTotal], contains('24,350'));
  });

  test('budget percent is integer-exact, left never negative', () {
    final snap = buildWidgetSnapshot(
      todayTotal: Money.zero,
      monthTotal: Money.parse('24000'),
      budget: Money.parse('40000'),
      trend: flatTrend(),
      quickAddCategories: cats,
      now: now,
    );
    expect(snap[WidgetKeys.budgetPct], '60'); // 24000/40000
    expect(snap[WidgetKeys.hasBudget], 'true');

    // Overspent: pct clamps to 100, left clamps to 0 (never negative).
    final over = buildWidgetSnapshot(
      todayTotal: Money.zero,
      monthTotal: Money.parse('50000'),
      budget: Money.parse('40000'),
      trend: flatTrend(),
      quickAddCategories: cats,
      now: now,
    );
    expect(over[WidgetKeys.budgetPct], '100');
    expect(over[WidgetKeys.budgetLeft], contains('0'));
  });

  test('no budget → pct 0, hasBudget false', () {
    final snap = buildWidgetSnapshot(
      todayTotal: Money.zero,
      monthTotal: Money.parse('100'),
      budget: null,
      trend: flatTrend(),
      quickAddCategories: cats,
      now: now,
    );
    expect(snap[WidgetKeys.budgetPct], '0');
    expect(snap[WidgetKeys.hasBudget], 'false');
  });

  test('trend serializes 6 bars with heights relative to the tallest', () {
    // Two months with spend, tallest is the second → 100.
    final trend = <TrendBar>[
      ('Feb', Money.parse('500'), false),
      ('Mar', Money.parse('1000'), false),
      ('Apr', Money.zero, false),
      ('May', Money.zero, false),
      ('Jun', Money.zero, false),
      ('Jul', Money.zero, true),
    ];
    final snap = buildWidgetSnapshot(
      todayTotal: Money.zero,
      monthTotal: Money.zero,
      budget: null,
      trend: trend,
      quickAddCategories: cats,
      now: now,
    );
    final bars = jsonDecode(snap[WidgetKeys.trend]!) as List;
    expect(bars.length, 6);
    expect(bars[0]['heightPct'], 50); // 500 of 1000
    expect(bars[1]['heightPct'], 100); // tallest
    expect(bars[2]['heightPct'], 0);
  });

  test('flat trend (all zero) produces zero heights, not a divide-by-zero', () {
    final snap = buildWidgetSnapshot(
      todayTotal: Money.zero,
      monthTotal: Money.zero,
      budget: null,
      trend: flatTrend(),
      quickAddCategories: cats,
      now: now,
    );
    final bars = jsonDecode(snap[WidgetKeys.trend]!) as List;
    expect(bars.every((b) => b['heightPct'] == 0), isTrue);
  });

  test('quick-add caps at 4 categories, carries id/icon/name', () {
    final snap = buildWidgetSnapshot(
      todayTotal: Money.zero,
      monthTotal: Money.zero,
      budget: null,
      trend: flatTrend(),
      quickAddCategories: cats, // 8 defaults
      now: now,
    );
    final quick = jsonDecode(snap[WidgetKeys.quickAdd]!) as List;
    expect(quick.length, 4);
    expect(quick.first['id'], cats.first.id);
    expect(quick.first['name'], cats.first.name);
    expect(quick.first['icon'], isNotEmpty);
  });
}

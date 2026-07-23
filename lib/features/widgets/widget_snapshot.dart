import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../../core/db/database.dart';
import '../../core/money/money.dart';
import '../home/dashboard_providers.dart';

/// App Group / shared-prefs id — MUST match the iOS Runner + widget-extension
/// entitlements and the Android provider. Change in lockstep.
const widgetAppGroupId = 'group.com.spendly.spendly';

/// iOS WidgetKit kinds — one per widget in the bundle (they all read the same
/// snapshot, so all four are reloaded after a write). Must match the `kind:`
/// strings in `ios/SpendlyWidget/SpendlyWidget.swift`.
const iOSWidgetKinds = [
  'SpendlyTodayWidget',
  'SpendlyQuickAddWidget',
  'SpendlyMonthWidget',
  'SpendlyLockWidget',
];

/// Android Glance receiver — fully-qualified so `home_widget` finds it in the
/// `.widget` subpackage. One responsive receiver serves all sizes. Must match
/// the manifest registration.
const androidWidgetReceiver =
    'com.spendly.spendly.widget.SpendlyWidgetReceiver';

/// Snapshot keys the native widgets read. Kept as constants so Dart and the
/// Swift/Kotlin sides can't silently drift apart.
class WidgetKeys {
  WidgetKeys._();
  static const todayTotal = 'todayTotal';
  static const monthTotal = 'monthTotal';
  static const budgetPct = 'budgetPct'; // 0-100, 0 = no budget
  static const budgetLeft = 'budgetLeft';
  static const hasBudget = 'hasBudget';
  static const trend = 'trend'; // JSON array of {label, heightPct}
  static const quickAdd = 'quickAdd'; // JSON array of {id, icon, name}
  static const updatedAt = 'updatedAt';
}

/// Locale used for the money strings the widgets display. Single-currency v1
/// (matches the app default); the native side only ever renders these strings.
const _widgetLocale = 'en_IN';

/// Build the flat, JSON-serializable snapshot the native widgets read (FR-26,
/// FR-27, FR-28, FR-4). Pure so it's unit-testable — no DB, no `home_widget`.
/// All money is already computed app-side from integer minor units; the widget
/// never does math.
Map<String, String> buildWidgetSnapshot({
  required Money todayTotal,
  required Money monthTotal,
  required Money? budget,
  required List<TrendBar> trend,
  required List<CategoryRow> quickAddCategories,
  required DateTime now,
}) {
  final hasBudget = budget != null && budget.minor > 0;
  final pct = hasBudget
      ? (monthTotal.ratioOf(budget).clamp(0.0, 1.0) * 100).round()
      : 0;
  final left = hasBudget
      ? Money.fromMinor(
          (budget.minor - monthTotal.minor).clamp(0, budget.minor),
        )
      : Money.zero;

  // Trend bar heights as 0-100 ints relative to the tallest month (so the
  // native mini-bars need no scaling logic). Flat month = all zero-height.
  final maxMinor = trend.fold<int>(
    0,
    (m, b) => b.$2.minor > m ? b.$2.minor : m,
  );
  final trendJson = [
    for (final (label, total, _) in trend)
      {
        'label': label,
        'heightPct': maxMinor == 0 ? 0 : (total.minor * 100 / maxMinor).round(),
      },
  ];

  final quickAddJson = [
    for (final c in quickAddCategories.take(4))
      {'id': c.id, 'icon': c.icon, 'name': c.name},
  ];

  return {
    WidgetKeys.todayTotal: todayTotal.format(locale: _widgetLocale),
    WidgetKeys.monthTotal: monthTotal.format(locale: _widgetLocale),
    WidgetKeys.budgetPct: pct.toString(),
    WidgetKeys.budgetLeft: left.format(locale: _widgetLocale),
    WidgetKeys.hasBudget: hasBudget.toString(),
    WidgetKeys.trend: jsonEncode(trendJson),
    WidgetKeys.quickAdd: jsonEncode(quickAddJson),
    WidgetKeys.updatedAt: now.toIso8601String(),
  };
}

/// Thin wrapper over `home_widget`: owns the shared store and the update call.
class WidgetBridge {
  Future<void> init() => HomeWidget.setAppGroupId(widgetAppGroupId);

  Future<void> write(Map<String, String> snapshot) async {
    await HomeWidget.setAppGroupId(widgetAppGroupId);
    for (final entry in snapshot.entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
    // Reload the Android receiver once and each iOS kind (all read the same
    // data). updateWidget maps iOSName → WidgetCenter.reloadTimelines(ofKind:).
    await HomeWidget.updateWidget(qualifiedAndroidName: androidWidgetReceiver);
    for (final kind in iOSWidgetKinds) {
      await HomeWidget.updateWidget(iOSName: kind);
    }
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/widgets/widget_snapshot.dart';

/// Guards docs/known-issues.md push-back #2 (widget-bridge schema
/// triplication): the snapshot's key names, widget-kind strings, the
/// Android receiver class, and the App Group id are each hand-declared
/// independently in Dart (`widget_snapshot.dart`), Swift
/// (`SpendlyWidget.swift`), and Kotlin (`SpendlyGlanceWidget.kt`,
/// `SpendlyWidgetReceiver.kt`) with nothing enforcing they stay in sync —
/// already caused two shipped bugs (`dd6724f`, `9fc2c9e`). A source-text
/// scan, not a build/codegen check (ADR-005 calls full codegen
/// disproportionate for ~6-8 keys), same style as
/// `reactive_read_staleness_test.dart` and `migration_test.dart`: it fails
/// the moment a key is renamed/removed on one side without the others being
/// updated to match.
void main() {
  late String swift;
  late String kotlin;
  late String receiver;
  late String entitlements;

  setUpAll(() {
    swift = File('ios/SpendlyWidget/SpendlyWidget.swift').readAsStringSync();
    kotlin = File(
      'android/app/src/main/kotlin/com/spendly/spendly/widget/SpendlyGlanceWidget.kt',
    ).readAsStringSync();
    receiver = File(
      'android/app/src/main/kotlin/com/spendly/spendly/widget/SpendlyWidgetReceiver.kt',
    ).readAsStringSync();
    entitlements = File(
      'ios/SpendlyWidget/SpendlyWidget.entitlements',
    ).readAsStringSync();
  });

  test('iOS Swift source still references every WidgetKeys constant', () {
    final missing = <String>[];
    for (final key in [
      WidgetKeys.todayTotal,
      WidgetKeys.monthTotal,
      WidgetKeys.budgetPct,
      WidgetKeys.budgetLeft,
      WidgetKeys.hasBudget,
      WidgetKeys.trend,
      WidgetKeys.quickAdd,
    ]) {
      if (!swift.contains('"$key"')) missing.add(key);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'SpendlyWidget.swift no longer references snapshot key(s) $missing '
          '— a key was renamed/removed in widget_snapshot.dart without '
          'updating the iOS widget to match.',
    );
  });

  test('iOS Swift source still declares every widget kind', () {
    final missing = iOSWidgetKinds.where((k) => !swift.contains('"$k"'));
    expect(
      missing,
      isEmpty,
      reason:
          'SpendlyWidget.swift is missing widget kind(s) $missing declared '
          'in iOSWidgetKinds (widget_snapshot.dart) — reloadTimelines(ofKind:) '
          'for that kind would silently no-op.',
    );
  });

  test('Android Kotlin source still references the keys it reads', () {
    final androidReadKeys = [
      WidgetKeys.todayTotal,
      WidgetKeys.monthTotal,
      WidgetKeys.budgetPct,
      WidgetKeys.budgetLeft,
      WidgetKeys.hasBudget,
      WidgetKeys.quickAdd,
    ];
    final missing = androidReadKeys.where((k) => !kotlin.contains('"$k"'));
    expect(
      missing,
      isEmpty,
      reason:
          'SpendlyGlanceWidget.kt no longer references snapshot key(s) '
          '$missing — a key was renamed/removed in widget_snapshot.dart '
          'without updating the Android widget to match.',
    );
  });

  test('Android receiver still binds the declared Glance widget class', () {
    final className = androidWidgetReceiver.split('.').last;
    expect(
      receiver.contains(className),
      isTrue,
      reason:
          'SpendlyWidgetReceiver.kt no longer references $className — '
          'androidWidgetReceiver (widget_snapshot.dart) would resolve to a '
          'receiver home_widget can\'t find at runtime.',
    );
  });

  test('App Group id matches across Dart source and iOS entitlements', () {
    expect(swift.contains('"$widgetAppGroupId"'), isTrue,
        reason: 'SpendlyWidget.swift app group id no longer matches '
            'widgetAppGroupId (widget_snapshot.dart).');
    expect(entitlements.contains(widgetAppGroupId), isTrue,
        reason: 'SpendlyWidget.entitlements app group id no longer matches '
            'widgetAppGroupId (widget_snapshot.dart).');
  });
}

import 'package:drift/drift.dart' show Value;

import '../../core/db/database.dart';

/// JSON-safe DTOs for the backup format (`docs/backup-schema.md`). Kept
/// separate from the Drift row classes so the on-disk JSON shape is pinned
/// independently of the DB schema — a future schema change shouldn't silently
/// change what old backups decode to.

class BackupCategory {
  const BackupCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorValue,
    required this.sortOrder,
    required this.isArchived,
    required this.isDefault,
  });

  final int id;
  final String name;
  final String icon;
  final int colorValue;
  final int sortOrder;
  final bool isArchived;
  final bool isDefault;

  factory BackupCategory.fromRow(CategoryRow row) => BackupCategory(
        id: row.id,
        name: row.name,
        icon: row.icon,
        colorValue: row.colorValue,
        sortOrder: row.sortOrder,
        isArchived: row.isArchived,
        isDefault: row.isDefault,
      );

  factory BackupCategory.fromJson(Map<String, dynamic> j) => BackupCategory(
        id: j['id'] as int,
        name: j['name'] as String,
        icon: j['icon'] as String,
        colorValue: j['colorValue'] as int,
        sortOrder: j['sortOrder'] as int,
        isArchived: j['isArchived'] as bool,
        isDefault: j['isDefault'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'colorValue': colorValue,
        'sortOrder': sortOrder,
        'isArchived': isArchived,
        'isDefault': isDefault,
      };

  /// Merge: new row, id auto-assigned; caller picks the append-order slot.
  CategoriesCompanion toInsertCompanion({required int sortOrder}) =>
      CategoriesCompanion.insert(
        name: name,
        icon: icon,
        colorValue: colorValue,
        sortOrder: Value(sortOrder),
        isArchived: Value(isArchived),
        isDefault: Value(isDefault),
      );

  /// Replace: tables are wiped first, so the original id is reused verbatim.
  CategoriesCompanion toReplaceCompanion() => CategoriesCompanion(
        id: Value(id),
        name: Value(name),
        icon: Value(icon),
        colorValue: Value(colorValue),
        sortOrder: Value(sortOrder),
        isArchived: Value(isArchived),
        isDefault: Value(isDefault),
      );
}

class BackupExpense {
  const BackupExpense({
    required this.id,
    required this.amountMinor,
    required this.categoryId,
    required this.date,
    required this.note,
    required this.paymentMethod,
    required this.isRecurring,
    required this.recurrence,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int amountMinor;
  final int categoryId;
  final DateTime date;
  final String? note;
  final String? paymentMethod;
  final bool isRecurring;
  final Recurrence? recurrence;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BackupExpense.fromRow(ExpenseRow row) => BackupExpense(
        id: row.id,
        amountMinor: row.amountMinor,
        categoryId: row.categoryId,
        date: row.date,
        note: row.note,
        paymentMethod: row.paymentMethod,
        isRecurring: row.isRecurring,
        recurrence: row.recurrence,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  factory BackupExpense.fromJson(Map<String, dynamic> j) => BackupExpense(
        id: j['id'] as int,
        amountMinor: j['amountMinor'] as int,
        categoryId: j['categoryId'] as int,
        date: DateTime.parse(j['date'] as String),
        note: j['note'] as String?,
        paymentMethod: j['paymentMethod'] as String?,
        isRecurring: j['isRecurring'] as bool,
        recurrence: j['recurrence'] == null
            ? null
            : Recurrence.values.byName(j['recurrence'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amountMinor': amountMinor,
        'categoryId': categoryId,
        'date': date.toIso8601String(),
        'note': note,
        'paymentMethod': paymentMethod,
        'isRecurring': isRecurring,
        'recurrence': recurrence?.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Merge: new row, id auto-assigned; [mappedCategoryId] is the local
  /// category id the backup's categoryId was resolved to.
  ExpensesCompanion toInsertCompanion({required int mappedCategoryId}) =>
      ExpensesCompanion.insert(
        amountMinor: amountMinor,
        categoryId: mappedCategoryId,
        date: date,
        note: Value(note),
        paymentMethod: Value(paymentMethod),
        isRecurring: Value(isRecurring),
        recurrence: Value(recurrence),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
      );

  /// Replace: tables are wiped first, so the original id is reused verbatim.
  ExpensesCompanion toReplaceCompanion() => ExpensesCompanion(
        id: Value(id),
        amountMinor: Value(amountMinor),
        categoryId: Value(categoryId),
        date: Value(date),
        note: Value(note),
        paymentMethod: Value(paymentMethod),
        isRecurring: Value(isRecurring),
        recurrence: Value(recurrence),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
      );

  /// Content fingerprint used to dedupe on Merge — deliberately not the id,
  /// which isn't stable across devices/reinstalls. [mappedCategoryId] is the
  /// *local* category id (post name-match), so fingerprints compare like for
  /// like even when the backup's own category ids don't match this device's.
  String fingerprint({required int mappedCategoryId}) =>
      '$amountMinor|${date.toIso8601String()}|$mappedCategoryId|$note|$paymentMethod';
}

class BackupBudget {
  const BackupBudget({
    required this.id,
    required this.categoryId,
    required this.amountMinor,
    required this.period,
  });

  final int id;
  final int? categoryId;
  final int amountMinor;
  final BudgetPeriod period;

  factory BackupBudget.fromRow(BudgetRow row) => BackupBudget(
        id: row.id,
        categoryId: row.categoryId,
        amountMinor: row.amountMinor,
        period: row.period,
      );

  factory BackupBudget.fromJson(Map<String, dynamic> j) => BackupBudget(
        id: j['id'] as int,
        categoryId: j['categoryId'] as int?,
        amountMinor: j['amountMinor'] as int,
        period: BudgetPeriod.values.byName(j['period'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'amountMinor': amountMinor,
        'period': period.name,
      };

  /// Merge: new row, id auto-assigned; [mappedCategoryId] is null for the
  /// overall budget or the local category id the backup's slot resolved to.
  BudgetsCompanion toInsertCompanion({required int? mappedCategoryId}) =>
      BudgetsCompanion.insert(
        categoryId: Value(mappedCategoryId),
        amountMinor: amountMinor,
        period: Value(period),
      );

  /// Replace: tables are wiped first, so the original id is reused verbatim.
  BudgetsCompanion toReplaceCompanion() => BudgetsCompanion(
        id: Value(id),
        categoryId: Value(categoryId),
        amountMinor: Value(amountMinor),
        period: Value(period),
      );
}

class BackupSetting {
  const BackupSetting({required this.key, required this.value});

  final String key;
  final String? value;

  factory BackupSetting.fromRow(SettingRow row) =>
      BackupSetting(key: row.key, value: row.value);

  factory BackupSetting.fromJson(Map<String, dynamic> j) =>
      BackupSetting(key: j['key'] as String, value: j['value'] as String?);

  Map<String, dynamic> toJson() => {'key': key, 'value': value};

  SettingsCompanion toCompanion() =>
      SettingsCompanion.insert(key: key, value: Value(value));
}

/// The full exported dataset (`data` in the envelope). [exportedAt]/[counts]
/// are informational (drive the restore preview), not load-bearing for import.
class BackupPayload {
  const BackupPayload({
    required this.exportedAt,
    required this.categories,
    required this.expenses,
    required this.budgets,
    required this.settings,
  });

  final DateTime exportedAt;
  final List<BackupCategory> categories;
  final List<BackupExpense> expenses;
  final List<BackupBudget> budgets;
  final List<BackupSetting> settings;

  (DateTime, DateTime)? get expenseDateRange {
    if (expenses.isEmpty) return null;
    var min = expenses.first.date;
    var max = expenses.first.date;
    for (final e in expenses.skip(1)) {
      if (e.date.isBefore(min)) min = e.date;
      if (e.date.isAfter(max)) max = e.date;
    }
    return (min, max);
  }

  factory BackupPayload.fromJson(Map<String, dynamic> j) => BackupPayload(
        exportedAt: DateTime.parse(j['exportedAt'] as String),
        categories: (j['categories'] as List)
            .map((e) => BackupCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
        expenses: (j['expenses'] as List)
            .map((e) => BackupExpense.fromJson(e as Map<String, dynamic>))
            .toList(),
        budgets: (j['budgets'] as List)
            .map((e) => BackupBudget.fromJson(e as Map<String, dynamic>))
            .toList(),
        settings: (j['settings'] as List)
            .map((e) => BackupSetting.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'exportedAt': exportedAt.toIso8601String(),
        'counts': {
          'expenses': expenses.length,
          'categories': categories.length,
          'budgets': budgets.length,
        },
        'categories': categories.map((c) => c.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'budgets': budgets.map((b) => b.toJson()).toList(),
        'settings': settings.map((s) => s.toJson()).toList(),
      };
}

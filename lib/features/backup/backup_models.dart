import 'package:drift/drift.dart' show Value;

import '../../core/db/database.dart';
import '../../core/db/providers.dart' show SettingsRepository;

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
    required this.isIgnoredForBudget,
    required this.externalId,
  });

  final int id;
  final String name;
  final String icon;
  final int colorValue;
  final int sortOrder;
  final bool isArchived;
  final bool isDefault;
  final bool isIgnoredForBudget;

  /// Stable cross-device/cross-backup identity, preferred over name matching
  /// on Merge — see `docs/backup-schema.md`. Null for rows written before
  /// schema v7 that a legacy backup file predates entirely.
  final String? externalId;

  factory BackupCategory.fromRow(CategoryRow row) => BackupCategory(
    id: row.id,
    name: row.name,
    icon: row.icon,
    colorValue: row.colorValue,
    sortOrder: row.sortOrder,
    isArchived: row.isArchived,
    isDefault: row.isDefault,
    isIgnoredForBudget: row.isIgnoredForBudget,
    externalId: row.externalId,
  );

  factory BackupCategory.fromJson(Map<String, dynamic> j) => BackupCategory(
    id: j['id'] as int,
    name: j['name'] as String,
    icon: j['icon'] as String,
    colorValue: j['colorValue'] as int,
    sortOrder: j['sortOrder'] as int,
    isArchived: j['isArchived'] as bool,
    isDefault: j['isDefault'] as bool,
    // Additive — pre-Sprint-12 backups lack this key entirely.
    isIgnoredForBudget: j['isIgnoredForBudget'] as bool? ?? false,
    // Additive — pre-v7 backups lack this key entirely.
    externalId: j['externalId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'colorValue': colorValue,
    'sortOrder': sortOrder,
    'isArchived': isArchived,
    'isDefault': isDefault,
    'isIgnoredForBudget': isIgnoredForBudget,
    'externalId': externalId,
  };

  /// Merge: new row, id auto-assigned; caller picks the append-order slot.
  /// Carries the backup's externalId through if it had one, so a record
  /// merged from another device keeps its identity for the next merge too;
  /// otherwise the column's clientDefault assigns a fresh one.
  CategoriesCompanion toInsertCompanion({required int sortOrder}) =>
      CategoriesCompanion.insert(
        name: name,
        icon: icon,
        colorValue: colorValue,
        sortOrder: Value(sortOrder),
        isArchived: Value(isArchived),
        isDefault: Value(isDefault),
        isIgnoredForBudget: Value(isIgnoredForBudget),
        externalId: externalId == null
            ? const Value.absent()
            : Value(externalId),
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
    isIgnoredForBudget: Value(isIgnoredForBudget),
    externalId: externalId == null
        ? const Value.absent()
        : Value(externalId),
  );
}

class BackupTag {
  const BackupTag({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isArchived,
    required this.externalId,
    required this.fxCurrency,
    required this.fxRateMicros,
    required this.tripStartDate,
    required this.tripEndDate,
  });

  final int id;
  final String name;
  final int colorValue;
  final bool isArchived;
  final String? externalId;

  /// Trip-abroad currency + rate (backup v4). Null on an ordinary tag, and on
  /// every tag in a pre-v4 file.
  final String? fxCurrency;
  final int? fxRateMicros;

  /// Trip date range for auto-tagging (backup v5). Independent of
  /// [fxCurrency] — null on a tag with no date range, and on every tag in a
  /// pre-v5 file.
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;

  factory BackupTag.fromRow(TagRow row) => BackupTag(
    id: row.id,
    name: row.name,
    colorValue: row.colorValue,
    isArchived: row.isArchived,
    externalId: row.externalId,
    fxCurrency: row.fxCurrency,
    fxRateMicros: row.fxRateMicros,
    tripStartDate: row.tripStartDate,
    tripEndDate: row.tripEndDate,
  );

  factory BackupTag.fromJson(Map<String, dynamic> j) => BackupTag(
    id: j['id'] as int,
    name: j['name'] as String,
    colorValue: j['colorValue'] as int,
    isArchived: j['isArchived'] as bool,
    externalId: j['externalId'] as String?,
    // Pre-v4 files have no fx keys; absent = an ordinary, non-travel tag.
    fxCurrency: j['fxCurrency'] as String?,
    fxRateMicros: j['fxRateMicros'] as int?,
    // Pre-v5 files have no trip-date keys; absent = no auto-tagging.
    tripStartDate: j['tripStartDate'] == null
        ? null
        : DateTime.parse(j['tripStartDate'] as String),
    tripEndDate: j['tripEndDate'] == null
        ? null
        : DateTime.parse(j['tripEndDate'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'isArchived': isArchived,
    'externalId': externalId,
    'fxCurrency': fxCurrency,
    'fxRateMicros': fxRateMicros,
    'tripStartDate': tripStartDate?.toIso8601String(),
    'tripEndDate': tripEndDate?.toIso8601String(),
  };

  /// Merge: new row, id auto-assigned.
  TagsCompanion toInsertCompanion() => TagsCompanion.insert(
    name: name,
    colorValue: colorValue,
    isArchived: Value(isArchived),
    externalId: externalId == null
        ? const Value.absent()
        : Value(externalId),
    fxCurrency: Value(fxCurrency),
    fxRateMicros: Value(fxRateMicros),
    tripStartDate: Value(tripStartDate),
    tripEndDate: Value(tripEndDate),
  );

  /// Replace: tables are wiped first, so the original id is reused verbatim.
  TagsCompanion toReplaceCompanion() => TagsCompanion(
    id: Value(id),
    name: Value(name),
    colorValue: Value(colorValue),
    isArchived: Value(isArchived),
    externalId: externalId == null
        ? const Value.absent()
        : Value(externalId),
    fxCurrency: Value(fxCurrency),
    fxRateMicros: Value(fxRateMicros),
    tripStartDate: Value(tripStartDate),
    tripEndDate: Value(tripEndDate),
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
    required this.tagId,
    required this.createdAt,
    required this.updatedAt,
    required this.externalId,
    required this.fxCurrency,
    required this.fxAmountMinor,
  });

  final int id;
  final int amountMinor;
  final int categoryId;
  final DateTime date;
  final String? note;
  final String? paymentMethod;
  final bool isRecurring;
  final Recurrence? recurrence;

  /// Backup-file id of the trip/tag this expense carried, or null. Resolved
  /// to a local tag id via the tag-id map on merge/replace — see
  /// [BackupRepository].
  final int? tagId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? externalId;

  /// Foreign receipt (backup v4): what was actually paid abroad. Display
  /// only — [amountMinor] is home currency and stays the source of truth for
  /// every total, so a pre-v4 file restores as an ordinary expense.
  final String? fxCurrency;
  final int? fxAmountMinor;

  factory BackupExpense.fromRow(ExpenseRow row) => BackupExpense(
    id: row.id,
    amountMinor: row.amountMinor,
    categoryId: row.categoryId,
    date: row.date,
    note: row.note,
    paymentMethod: row.paymentMethod,
    isRecurring: row.isRecurring,
    recurrence: row.recurrence,
    tagId: row.tagId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    externalId: row.externalId,
    fxCurrency: row.fxCurrency,
    fxAmountMinor: row.fxAmountMinor,
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
    // Pre-trip-feature backups have no "tagId" key; absent = untagged.
    tagId: j['tagId'] as int?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    externalId: j['externalId'] as String?,
    // Pre-v4 files have no fx keys; absent = a home-currency expense.
    fxCurrency: j['fxCurrency'] as String?,
    fxAmountMinor: j['fxAmountMinor'] as int?,
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
    'tagId': tagId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'externalId': externalId,
    'fxCurrency': fxCurrency,
    'fxAmountMinor': fxAmountMinor,
  };

  /// Merge: new row, id auto-assigned; [mappedCategoryId] is the local
  /// category id the backup's categoryId was resolved to; [mappedTagId] is
  /// the local tag id the backup's tagId was resolved to (null if untagged).
  ExpensesCompanion toInsertCompanion({
    required int mappedCategoryId,
    required int? mappedTagId,
  }) => ExpensesCompanion.insert(
    amountMinor: amountMinor,
    categoryId: mappedCategoryId,
    date: date,
    note: Value(note),
    paymentMethod: Value(paymentMethod),
    isRecurring: Value(isRecurring),
    recurrence: Value(recurrence),
    tagId: Value(mappedTagId),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    externalId: externalId == null
        ? const Value.absent()
        : Value(externalId),
    fxCurrency: Value(fxCurrency),
    fxAmountMinor: Value(fxAmountMinor),
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
    tagId: Value(tagId),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    externalId: externalId == null
        ? const Value.absent()
        : Value(externalId),
    fxCurrency: Value(fxCurrency),
    fxAmountMinor: Value(fxAmountMinor),
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
    required this.monthKey,
    required this.externalId,
  });

  final int id;
  final int? categoryId;
  final int amountMinor;
  final BudgetPeriod period;
  final String monthKey;
  final String? externalId;

  factory BackupBudget.fromRow(BudgetRow row) => BackupBudget(
    id: row.id,
    categoryId: row.categoryId,
    amountMinor: row.amountMinor,
    period: row.period,
    monthKey: row.monthKey,
    externalId: row.externalId,
  );

  factory BackupBudget.fromJson(Map<String, dynamic> j) => BackupBudget(
    id: j['id'] as int,
    categoryId: j['categoryId'] as int?,
    amountMinor: j['amountMinor'] as int,
    period: BudgetPeriod.values.byName(j['period'] as String),
    // Older backups predate per-month budgets; treat them as the current month.
    monthKey: j['monthKey'] as String? ?? monthKeyFor(DateTime.now()),
    externalId: j['externalId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'amountMinor': amountMinor,
    'period': period.name,
    'monthKey': monthKey,
    'externalId': externalId,
  };

  /// Merge: new row, id auto-assigned; [mappedCategoryId] is null for the
  /// overall budget or the local category id the backup's slot resolved to.
  BudgetsCompanion toInsertCompanion({required int? mappedCategoryId}) =>
      BudgetsCompanion.insert(
        categoryId: Value(mappedCategoryId),
        amountMinor: amountMinor,
        period: Value(period),
        monthKey: monthKey,
        externalId: externalId == null
            ? const Value.absent()
            : Value(externalId),
      );

  /// Replace: tables are wiped first, so the original id is reused verbatim.
  BudgetsCompanion toReplaceCompanion() => BudgetsCompanion(
    id: Value(id),
    categoryId: Value(categoryId),
    amountMinor: Value(amountMinor),
    period: Value(period),
    monthKey: Value(monthKey),
    externalId: externalId == null
        ? const Value.absent()
        : Value(externalId),
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
    required this.tags,
  });

  final DateTime exportedAt;
  final List<BackupCategory> categories;
  final List<BackupExpense> expenses;
  final List<BackupBudget> budgets;
  final List<BackupSetting> settings;
  final List<BackupTag> tags;

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

  factory BackupPayload.fromJson(Map<String, dynamic> j) {
    final settings = (j['settings'] as List)
        .map((e) => BackupSetting.fromJson(e as Map<String, dynamic>))
        .toList();
    // Legacy v2 backups carried the photo in its own top-level key instead
    // of as an ordinary setting — fold it in so old exports still restore.
    final legacyPhoto = j['profilePhotoBase64'] as String?;
    if (legacyPhoto != null &&
        !settings.any(
          (s) => s.key == SettingsRepository.profilePhotoBase64Key,
        )) {
      settings.add(
        BackupSetting(
          key: SettingsRepository.profilePhotoBase64Key,
          value: legacyPhoto,
        ),
      );
    }

    return BackupPayload(
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
      settings: settings,
      // Pre-trip-feature backups have no "tags" key at all.
      tags: j['tags'] == null
          ? const []
          : (j['tags'] as List)
                .map((e) => BackupTag.fromJson(e as Map<String, dynamic>))
                .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'exportedAt': exportedAt.toIso8601String(),
    'counts': {
      'expenses': expenses.length,
      'categories': categories.length,
      'budgets': budgets.length,
      'tags': tags.length,
    },
    'categories': categories.map((c) => c.toJson()).toList(),
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'budgets': budgets.map((b) => b.toJson()).toList(),
    'settings': settings.map((s) => s.toJson()).toList(),
    'tags': tags.map((t) => t.toJson()).toList(),
  };
}

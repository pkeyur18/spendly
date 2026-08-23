import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';

/// Tag CRUD — user-defined grouping across categories (e.g. a vacation trip).
/// Archive hides a tag from the picker without touching anything. Delete is
/// always allowed (unlike [CategoryRepository.tryDelete], which blocks when
/// referenced) — a tag is optional metadata on an expense, so deleting one
/// just clears `tagId` on whatever expenses carried it; the expenses
/// themselves are never touched.
class TagRepository {
  TagRepository(this._db);
  final AppDatabase _db;

  Stream<List<TagRow>> watchAll() {
    return (_db.select(
      _db.tags,
    )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).watch();
  }

  /// Active (non-archived) tags shown in the expense entry picker.
  Stream<List<TagRow>> watchActive() {
    return (_db.select(_db.tags)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  /// [fxCurrency] + [fxRateMicros] mark the tag as a trip abroad; both null
  /// for an ordinary tag. They travel together — a currency with no rate can't
  /// convert anything.
  ///
  /// [tripStartDate] + [tripEndDate] are independent of the currency pair —
  /// they drive auto-tagging (see [tripForDate]) and work for a domestic trip
  /// too. Also travel together; both required or both omitted.
  Future<int> create({
    required String name,
    required int colorValue,
    String? fxCurrency,
    int? fxRateMicros,
    DateTime? tripStartDate,
    DateTime? tripEndDate,
  }) {
    return _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            name: name,
            colorValue: colorValue,
            fxCurrency: Value(fxCurrency),
            fxRateMicros: Value(fxRateMicros),
            tripStartDate: Value(tripStartDate),
            tripEndDate: Value(tripEndDate),
          ),
        );
  }

  Future<void> rename(int id, String name) => _update(id, name: Value(name));
  Future<void> recolor(int id, int colorValue) =>
      _update(id, colorValue: Value(colorValue));

  /// Updates the rate used for FUTURE expenses on this trip. Already-saved
  /// expenses keep the home-currency amount they were converted to — see
  /// `lib/core/money/fx.dart`.
  Future<void> setFxRate(int id, int rateMicros) =>
      _update(id, fxRateMicros: Value(rateMicros));

  /// Turns travel mode on or off. Pass nulls to make it an ordinary tag again.
  Future<void> setCurrency(int id, String? currencyCode, int? rateMicros) =>
      _update(
        id,
        fxCurrency: Value(currencyCode),
        fxRateMicros: Value(rateMicros),
      );

  /// Sets or clears the trip date range. Pass both null to turn off
  /// auto-tagging for this trip.
  Future<void> setTripDates(int id, DateTime? start, DateTime? end) => _update(
    id,
    tripStartDate: Value(start),
    tripEndDate: Value(end),
  );

  /// Truncates to the calendar date, dropping time of day — every trip-range
  /// comparison in this class is date-only.
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Date-only, inclusive range check — matches [tripForDate] and
  /// [hasOverlappingDateRange]'s own comparison, in one place.
  static bool _covers(TagRow t, DateTime day) {
    if (t.tripStartDate == null || t.tripEndDate == null) return false;
    final d = _dateOnly(day);
    return !d.isBefore(_dateOnly(t.tripStartDate!)) &&
        !d.isAfter(_dateOnly(t.tripEndDate!));
  }

  /// The active trip whose date range covers [date], or null. Fresh one-shot
  /// read — used by quick-add's auto-tag lookup, which needs a
  /// guaranteed-current answer at save time, not a cached stream value.
  Future<TagRow?> tripForDate(DateTime date) async {
    final active = await (_db.select(
      _db.tags,
    )..where((t) => t.isArchived.equals(false))).get();
    return active.where((t) => _covers(t, date)).cast<TagRow?>().firstOrNull;
  }

  /// Whether [start]..[end] (inclusive) overlaps any OTHER active trip's
  /// date range. Guards `tag_edit_sheet`'s save path — two trips claiming the
  /// same day would make auto-tagging ambiguous, so it's blocked outright
  /// rather than picked arbitrarily. [excludeId] is the tag being edited, so
  /// it doesn't collide with its own unchanged dates.
  Future<bool> hasOverlappingDateRange(
    int? excludeId,
    DateTime start,
    DateTime end,
  ) async {
    final active = await (_db.select(
      _db.tags,
    )..where((t) => t.isArchived.equals(false))).get();
    final s = _dateOnly(start);
    final e = _dateOnly(end);
    return active.any((t) {
      if (t.id == excludeId) return false;
      if (t.tripStartDate == null || t.tripEndDate == null) return false;
      final otherStart = _dateOnly(t.tripStartDate!);
      final otherEnd = _dateOnly(t.tripEndDate!);
      return !s.isAfter(otherEnd) && !e.isBefore(otherStart);
    });
  }

  /// Fresh one-shot read of a single tag, or null if it's gone.
  ///
  /// For post-write logic that needs a guaranteed-current rate — reading the
  /// cached `activeTagsProvider` there would serve a value that lags a write
  /// by a microtask (docs/known-issues.md #1, and see
  /// `test/reactive_read_staleness_test.dart`).
  Future<TagRow?> byId(int id) {
    return (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Whether any expense currently carries this tag. Guards changing a trip's
  /// currency: a tag mixing baht and dirham rows makes its own total
  /// meaningless, so the editor blocks the switch once expenses exist.
  Future<bool> hasExpenses(int id) async {
    final count = _db.expenses.id.count();
    final row =
        await (_db.selectOnly(_db.expenses)
              ..addColumns([count])
              ..where(_db.expenses.tagId.equals(id)))
            .getSingle();
    return (row.read(count) ?? 0) > 0;
  }
  Future<void> archive(int id) => _update(id, isArchived: const Value(true));
  Future<void> unarchive(int id) => _update(id, isArchived: const Value(false));

  /// Deletes the tag; any expense carrying it silently drops back to
  /// untagged. One transaction so the untag-then-delete is atomic.
  Future<void> delete(int id) {
    return _db.transaction(() async {
      await (_db.update(_db.expenses)..where((t) => t.tagId.equals(id))).write(
        const ExpensesCompanion(tagId: Value(null)),
      );
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> _update(
    int id, {
    Value<String> name = const Value.absent(),
    Value<int> colorValue = const Value.absent(),
    Value<bool> isArchived = const Value.absent(),
    Value<String?> fxCurrency = const Value.absent(),
    Value<int?> fxRateMicros = const Value.absent(),
    Value<DateTime?> tripStartDate = const Value.absent(),
    Value<DateTime?> tripEndDate = const Value.absent(),
  }) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(
        name: name,
        colorValue: colorValue,
        isArchived: isArchived,
        fxCurrency: fxCurrency,
        fxRateMicros: fxRateMicros,
        tripStartDate: tripStartDate,
        tripEndDate: tripEndDate,
      ),
    );
  }
}

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(databaseProvider)),
);

final activeTagsProvider = StreamProvider<List<TagRow>>(
  (ref) => ref.watch(tagRepositoryProvider).watchActive(),
);

final allTagsProvider = StreamProvider<List<TagRow>>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll(),
);

/// Every tag (active and archived — a past expense may reference an
/// archived one) keyed by id, same pattern as `categoriesByIdProvider`.
/// Feeds the Excel/PDF export's Trip column.
final tagsByIdProvider = Provider<Map<int, TagRow>>((ref) {
  final tags = ref.watch(allTagsProvider).value ?? const [];
  return {for (final t in tags) t.id: t};
});

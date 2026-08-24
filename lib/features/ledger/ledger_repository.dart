import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/money/money.dart';
import '../../core/notify/notifications.dart';
import '../expenses/recurring_schedule.dart';
import '../reports/report_providers.dart' show DateRange;

/// One recurring income template together with the occurrences currently
/// waiting on the user — the income-side twin of
/// `recurring_repository.dart`'s `RecurringSeries`.
typedef IncomeRecurringSeries = ({LedgerEntryRow template, List<DateTime> pending});

/// Income + transfer CRUD (schema v15, transfers added v16) — see
/// [LedgerEntries]'s doc comment for why this lives apart from
/// [ExpenseRepository]. Entries are hard-deleted: unlike
/// categories/tags/accounts, nothing else in the schema references a ledger
/// entry by id, so there's no history to protect by archiving instead.
class LedgerRepository {
  LedgerRepository(this._db);
  final AppDatabase _db;

  Future<LedgerEntryRow?> byId(int id) => (_db.select(
    _db.ledgerEntries,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> addIncome({
    required Money amount,
    required DateTime date,
    int? accountId,
    String? sourceLabel,
    String? note,
    bool isRecurring = false,
    Recurrence? recurrence,
    DateTime? nextDueDate,
    DateTime? recurrenceEndDate,
  }) => _db
      .into(_db.ledgerEntries)
      .insert(
        LedgerEntriesCompanion.insert(
          amountMinor: amount.minor,
          date: date,
          kind: const Value(LedgerEntryKind.income),
          accountId: Value(accountId),
          sourceLabel: Value(sourceLabel),
          note: Value(note),
          isRecurring: Value(isRecurring),
          recurrence: Value(recurrence),
          nextDueDate: Value(nextDueDate),
          recurrenceEndDate: Value(recurrenceEndDate),
        ),
      );

  /// [fromAccountId] and [toAccountId] must differ — moving money into the
  /// same account it left isn't a transfer, and would net to zero in the
  /// balance math anyway. Callers (the Transfer sheet) enforce this before
  /// calling; not re-checked here since it's a UI-level input constraint,
  /// not a data-integrity one this repository needs to defend on its own.
  Future<int> addTransfer({
    required Money amount,
    required DateTime date,
    required int fromAccountId,
    required int toAccountId,
    String? note,
  }) => _db
      .into(_db.ledgerEntries)
      .insert(
        LedgerEntriesCompanion.insert(
          amountMinor: amount.minor,
          date: date,
          kind: const Value(LedgerEntryKind.transfer),
          accountId: Value(fromAccountId),
          counterAccountId: Value(toAccountId),
          note: Value(note),
        ),
      );

  Future<void> update(
    int id, {
    Money? amount,
    DateTime? date,
    int? accountId,
    bool clearAccount = false,
    int? counterAccountId,
    String? sourceLabel,
    String? note,
    bool? isRecurring,
    Value<Recurrence?> recurrence = const Value.absent(),
    Value<DateTime?> nextDueDate = const Value.absent(),
    Value<DateTime?> recurrenceEndDate = const Value.absent(),
  }) => (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(id))).write(
    LedgerEntriesCompanion(
      amountMinor: amount == null ? const Value.absent() : Value(amount.minor),
      date: date == null ? const Value.absent() : Value(date),
      accountId: clearAccount
          ? const Value(null)
          : (accountId == null ? const Value.absent() : Value(accountId)),
      counterAccountId: counterAccountId == null
          ? const Value.absent()
          : Value(counterAccountId),
      sourceLabel: sourceLabel == null ? const Value.absent() : Value(sourceLabel),
      note: note == null ? const Value.absent() : Value(note),
      isRecurring: isRecurring == null
          ? const Value.absent()
          : Value(isRecurring),
      recurrence: recurrence,
      nextDueDate: nextDueDate,
      recurrenceEndDate: recurrenceEndDate,
    ),
  );

  Future<void> delete(int id) =>
      (_db.delete(_db.ledgerEntries)..where((t) => t.id.equals(id))).go();

  /// Puts a deleted row back exactly as it was — same id/externalId, backs
  /// the undo-a-delete snackbar. Same trick as `ExpenseRepository.restore`.
  Future<void> restore(LedgerEntryRow row) =>
      _db.into(_db.ledgerEntries).insert(row.toCompanion(false));

  /// Every income entry, newest first — feeds the Income screen. Transfers
  /// are deliberately excluded: they have their own home in the account
  /// detail timeline, not in a screen named "Income".
  Stream<List<LedgerEntryRow>> watchAll() {
    return (_db.select(_db.ledgerEntries)
          ..where((t) => t.kind.equalsValue(LedgerEntryKind.income))
          ..orderBy(
            [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)],
          ))
        .watch();
  }

  Stream<List<LedgerEntryRow>> watchInRange(DateTime start, DateTime end) {
    return (_db.select(_db.ledgerEntries)
          ..where(
            (t) =>
                t.kind.equalsValue(LedgerEntryKind.income) &
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
          ..orderBy(
            [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)],
          ))
        .watch();
  }

  /// Income total for a range, across every account — feeds the
  /// Recap/report savings-rate cards. Excludes transfers: moving money
  /// between your own accounts isn't income.
  Stream<Money> watchTotalInRange(DateTime start, DateTime end) {
    final sum = _db.ledgerEntries.amountMinor.sum();
    final query = _db.selectOnly(_db.ledgerEntries)
      ..addColumns([sum])
      ..where(
        _db.ledgerEntries.kind.equalsValue(LedgerEntryKind.income) &
            _db.ledgerEntries.date.isBiggerOrEqualValue(start) &
            _db.ledgerEntries.date.isSmallerThanValue(end),
      );
    return query.watchSingle().map((r) => Money.fromMinor(r.read(sum) ?? 0));
  }

  /// Income per account within [start, end) — one term of the account
  /// balance formula (`balance_math.dart`), grouped rather than one query per
  /// account so a dashboard-wide total costs one query, same shape as
  /// `AccountRepository.watchTotalsByAccount`. An account with no income in
  /// range is simply absent from the map, not present with zero.
  Stream<Map<int, Money>> watchIncomeTotalsByAccount(
    DateTime start,
    DateTime end,
  ) {
    final sum = _db.ledgerEntries.amountMinor.sum();
    final query = _db.selectOnly(_db.ledgerEntries)
      ..addColumns([_db.ledgerEntries.accountId, sum])
      ..where(
        _db.ledgerEntries.kind.equalsValue(LedgerEntryKind.income) &
            _db.ledgerEntries.accountId.isNotNull() &
            _db.ledgerEntries.date.isBiggerOrEqualValue(start) &
            _db.ledgerEntries.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.ledgerEntries.accountId]);
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.ledgerEntries.accountId)!: Money.fromMinor(
            r.read(sum) ?? 0,
          ),
      },
    );
  }

  /// Transfers OUT per source account within [start, end).
  Stream<Map<int, Money>> watchTransfersOutTotalsByAccount(
    DateTime start,
    DateTime end,
  ) {
    final sum = _db.ledgerEntries.amountMinor.sum();
    final query = _db.selectOnly(_db.ledgerEntries)
      ..addColumns([_db.ledgerEntries.accountId, sum])
      ..where(
        _db.ledgerEntries.kind.equalsValue(LedgerEntryKind.transfer) &
            _db.ledgerEntries.date.isBiggerOrEqualValue(start) &
            _db.ledgerEntries.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.ledgerEntries.accountId]);
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.ledgerEntries.accountId)!: Money.fromMinor(
            r.read(sum) ?? 0,
          ),
      },
    );
  }

  /// Transfers IN per destination account within [start, end).
  Stream<Map<int, Money>> watchTransfersInTotalsByAccount(
    DateTime start,
    DateTime end,
  ) {
    final sum = _db.ledgerEntries.amountMinor.sum();
    final query = _db.selectOnly(_db.ledgerEntries)
      ..addColumns([_db.ledgerEntries.counterAccountId, sum])
      ..where(
        _db.ledgerEntries.kind.equalsValue(LedgerEntryKind.transfer) &
            _db.ledgerEntries.date.isBiggerOrEqualValue(start) &
            _db.ledgerEntries.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.ledgerEntries.counterAccountId]);
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.ledgerEntries.counterAccountId)!: Money.fromMinor(
            r.read(sum) ?? 0,
          ),
      },
    );
  }

  /// Every ledger entry touching [accountId] within [start, end) — income
  /// landed in it, or a transfer that moved money in or out of it. Feeds the
  /// account detail screen's unioned timeline (expenses ∪ ledger entries),
  /// the one place these two tables are ever combined into a single list.
  Stream<List<LedgerEntryRow>> watchTouchingAccount(
    int accountId,
    DateTime start,
    DateTime end,
  ) {
    return (_db.select(_db.ledgerEntries)
          ..where(
            (t) =>
                (t.accountId.equals(accountId) |
                    t.counterAccountId.equals(accountId)) &
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
          ..orderBy(
            [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)],
          ))
        .watch();
  }

  /// Every income entry flagged recurring, newest first — templates, whether
  /// or not anything is due. Income-side twin of
  /// `RecurringRepository.watchTemplates`.
  Stream<List<LedgerEntryRow>> watchIncomeTemplates() {
    return (_db.select(_db.ledgerEntries)
          ..where(
            (t) =>
                t.kind.equalsValue(LedgerEntryKind.income) &
                t.isRecurring.equals(true),
          )
          ..orderBy(
            [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)],
          ))
        .watch();
  }

  /// Templates paired with their pending occurrences, as of [now].
  Stream<List<IncomeRecurringSeries>> watchIncomeSeries({DateTime? now}) {
    return watchIncomeTemplates().map((templates) {
      final at = now ?? DateTime.now();
      return [
        for (final template in templates)
          (
            template: template,
            pending: pendingOccurrences(
              nextDueDate: template.nextDueDate,
              recurrence: template.recurrence,
              endDate: template.recurrenceEndDate,
              anchorDay: template.date.day,
              now: at,
            ),
          ),
      ];
    });
  }

  /// Logs [occurrence] as a new, non-recurring income entry and advances
  /// [template]'s pointer past it — the income-side twin of
  /// `RecurringRepository.confirm`, except the logged fields are whatever the
  /// confirm sheet was left showing (possibly edited from the template),
  /// never the template's own values blindly copied: unlike an expense
  /// confirm (one silent tap), an income confirm is always a reviewed save.
  /// [occurrence] alone drives how the schedule advances, regardless of what
  /// [date] ends up being — paying a salary two days late doesn't shift every
  /// future payday.
  Future<void> confirmIncome(
    LedgerEntryRow template,
    DateTime occurrence, {
    required Money amount,
    required DateTime date,
    int? accountId,
    String? sourceLabel,
    String? note,
  }) async {
    await _db.transaction(() async {
      await addIncome(
        amount: amount,
        date: date,
        accountId: accountId,
        sourceLabel: sourceLabel,
        note: note,
      );
      await _advanceIncomePast(template, occurrence);
    });
  }

  /// Declines [occurrence] — nothing is logged, the pointer still moves on.
  Future<void> skipIncome(LedgerEntryRow template, DateTime occurrence) =>
      _advanceIncomePast(template, occurrence);

  /// Stops the series. The template row stays an ordinary (now non-
  /// recurring) income entry — the money it represents was really received
  /// when it was first logged, so cancelling a schedule must not delete
  /// history.
  Future<void> cancelIncomeRecurrence(LedgerEntryRow template) => update(
    template.id,
    isRecurring: false,
    nextDueDate: const Value(null),
  );

  Future<void> _advanceIncomePast(
    LedgerEntryRow template,
    DateTime resolved,
  ) {
    final next = nextDueAfter(
      resolved,
      template.recurrence,
      endDate: template.recurrenceEndDate,
      anchorDay: template.date.day,
    );
    return update(
      template.id,
      isRecurring: next != null,
      nextDueDate: Value(next),
    );
  }
}

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(databaseProvider)),
);

final allIncomeProvider = StreamProvider<List<LedgerEntryRow>>(
  (ref) => ref.watch(ledgerRepositoryProvider).watchAll(),
);

/// Income total for an arbitrary range — watched independently by Monthly
/// Recap and the report screens alongside their own expense total, then
/// combined via `cashflow_math.dart`. Kept as a sibling provider rather than
/// folded into `ReportData`/`buildReport`: those stay expense-only by the
/// same "separate ledger table" decision this whole table exists for.
final incomeTotalByRangeProvider = StreamProvider.family<Money, DateRange>(
  (ref, range) =>
      ref.watch(ledgerRepositoryProvider).watchTotalInRange(range.$1, range.$2),
);

/// Per-account income/transfer totals for a range — the three non-expense
/// terms of `balance_math.dart`'s formula, one query each across every
/// account rather than one query per account. Feeds both a single account's
/// balance card and the dashboard-wide total.
final incomeTotalsByAccountRangeProvider =
    StreamProvider.family<Map<int, Money>, DateRange>(
      (ref, range) => ref
          .watch(ledgerRepositoryProvider)
          .watchIncomeTotalsByAccount(range.$1, range.$2),
    );

final transfersOutTotalsByAccountRangeProvider =
    StreamProvider.family<Map<int, Money>, DateRange>(
      (ref, range) => ref
          .watch(ledgerRepositoryProvider)
          .watchTransfersOutTotalsByAccount(range.$1, range.$2),
    );

final transfersInTotalsByAccountRangeProvider =
    StreamProvider.family<Map<int, Money>, DateRange>(
      (ref, range) => ref
          .watch(ledgerRepositoryProvider)
          .watchTransfersInTotalsByAccount(range.$1, range.$2),
    );

/// Live recurring income series with their pending occurrences — feeds the
/// Recurring screen's Income tab and the Home due card. Income-side twin of
/// `recurring_repository.dart`'s `recurringSeriesProvider`.
final incomeRecurringSeriesProvider =
    StreamProvider<List<IncomeRecurringSeries>>(
      (ref) => ref.watch(ledgerRepositoryProvider).watchIncomeSeries(),
    );

/// Just the income series with something waiting, oldest due first — the
/// income-side twin of `recurring_repository.dart`'s `dueRecurringProvider`.
final dueIncomeRecurringProvider = Provider<List<IncomeRecurringSeries>>((
  ref,
) {
  final series = ref.watch(incomeRecurringSeriesProvider).value ?? const [];
  final due = [
    for (final s in series)
      if (s.pending.isNotEmpty) s,
  ];
  due.sort((a, b) => a.pending.first.compareTo(b.pending.first));
  return due;
});

/// Re-arms every recurring income reminder, on cold start and on resume —
/// income's twin of `recurring_repository.dart`'s
/// `recurringReminderCheckProvider`, same "watched not read" reasoning.
final incomeRecurringReminderCheckProvider = FutureProvider<void>((ref) async {
  final series = ref.watch(incomeRecurringSeriesProvider).value;
  if (series == null) return;

  final reminders = <({int id, String title, DateTime dueAt})>[];
  for (final s in series) {
    final due = s.template.nextDueDate;
    if (due == null) continue;
    reminders.add((
      id: s.template.id,
      title: s.template.sourceLabel?.isNotEmpty == true
          ? s.template.sourceLabel!
          : 'Income',
      dueAt: due,
    ));
  }
  await ref
      .read(notificationServiceProvider)
      .scheduleIncomeRecurringReminders(reminders);
});

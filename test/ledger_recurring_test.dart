import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/row_extensions.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/accounts/account_repository.dart';
import 'package:spendly/features/ledger/income_screen.dart';
import 'package:spendly/features/ledger/ledger_repository.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late AccountRepository accounts;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    accounts = AccountRepository(db);
  });
  tearDown(() => db.close());

  /// A monthly salary template first logged on 1 June, next due 1 July.
  Future<LedgerEntryRow> seedSalary({
    DateTime? nextDue,
    DateTime? endDate,
    DateTime? start,
  }) async {
    final id = await ledger.addIncome(
      amount: Money.parse('50000'),
      date: start ?? DateTime(2026, 6, 1),
      sourceLabel: 'Salary',
      isRecurring: true,
      recurrence: Recurrence.monthly,
      nextDueDate: nextDue ?? DateTime(2026, 7, 1),
      recurrenceEndDate: endDate,
    );
    return (await ledger.byId(id))!;
  }

  Future<LedgerEntryRow> reload(int id) async => (await ledger.byId(id))!;

  test('watchIncomeTemplates returns only recurring rows', () async {
    await seedSalary();
    await ledger.addIncome(amount: Money.parse('500'), date: DateTime(2026, 6, 5));

    final templates = await ledger.watchIncomeTemplates().first;
    expect(templates, hasLength(1));
    expect(templates.single.sourceLabel, 'Salary');
  });

  test('watchIncomeTemplates never returns a transfer', () async {
    final accountId = await accounts.create(name: 'Cash', type: AccountType.cash);
    final otherId = await accounts.create(name: 'Wallet', type: AccountType.wallet);
    await ledger.addTransfer(
      amount: Money.parse('100'),
      date: DateTime(2026, 6, 1),
      fromAccountId: accountId,
      toAccountId: otherId,
    );
    expect(await ledger.watchIncomeTemplates().first, isEmpty);
  });

  test('nothing is pending before the due date arrives', () async {
    final salary = await seedSalary();
    final series = await ledger.watchIncomeSeries(now: DateTime(2026, 6, 20)).first;
    expect(series.single.pending, isEmpty);
    expect(salary.sourceLabel, 'Salary'); // seeded row sanity check
  });

  test('two missed months surface as two pending occurrences', () async {
    await seedSalary();
    final series = await ledger.watchIncomeSeries(now: DateTime(2026, 8, 15)).first;
    expect(series.single.pending, [DateTime(2026, 7, 1), DateTime(2026, 8, 1)]);
  });

  group('confirmIncome', () {
    test('logs a new entry at the given date, not the occurrence blindly',
        () async {
      final salary = await seedSalary();
      // Reviewed and paid two days late — the log reflects that.
      await ledger.confirmIncome(
        salary,
        DateTime(2026, 7, 1),
        amount: salary.amount,
        date: DateTime(2026, 7, 3),
        sourceLabel: salary.sourceLabel,
      );

      final all = await ledger.watchInRange(DateTime(2026, 7, 1), DateTime(2026, 8, 1)).first;
      expect(all, hasLength(1));
      expect(all.single.date, DateTime(2026, 7, 3));
      expect(all.single.amount, Money.parse('50000'));
    });

    test('an edited amount is what gets logged, not the template amount',
        () async {
      final salary = await seedSalary();
      await ledger.confirmIncome(
        salary,
        DateTime(2026, 7, 1),
        amount: Money.parse('52000'), // a raise, reflected this month
        date: DateTime(2026, 7, 1),
      );

      final logged = (await ledger
              .watchInRange(DateTime(2026, 7, 1), DateTime(2026, 8, 1))
              .first)
          .single;
      expect(logged.amount, Money.parse('52000'));
    });

    test('the logged copy is not itself a template', () async {
      final salary = await seedSalary();
      await ledger.confirmIncome(
        salary,
        DateTime(2026, 7, 1),
        amount: salary.amount,
        date: DateTime(2026, 7, 1),
      );
      expect(await ledger.watchIncomeTemplates().first, hasLength(1));
    });

    test('advances the pointer past the confirmed occurrence, keyed off '
        'the occurrence not the edited date', () async {
      final salary = await seedSalary();
      await ledger.confirmIncome(
        salary,
        DateTime(2026, 7, 1),
        amount: salary.amount,
        date: DateTime(2026, 7, 3), // paid late
      );

      final updated = await reload(salary.id);
      expect(updated.nextDueDate, DateTime(2026, 8, 1));
    });
  });

  group('skipIncome', () {
    test('logs nothing but still moves the pointer on', () async {
      final salary = await seedSalary();
      await ledger.skipIncome(salary, DateTime(2026, 7, 1));

      expect(
        await ledger.watchInRange(DateTime(2026, 7, 1), DateTime(2026, 8, 1)).first,
        isEmpty,
      );
      expect((await reload(salary.id)).nextDueDate, DateTime(2026, 8, 1));
    });
  });

  group('end date', () {
    test('the series stops being a template after its last occurrence',
        () async {
      var salary = await seedSalary(endDate: DateTime(2026, 7, 15));
      await ledger.confirmIncome(
        salary,
        DateTime(2026, 7, 1),
        amount: salary.amount,
        date: DateTime(2026, 7, 1),
      );

      salary = await reload(salary.id);
      expect(salary.nextDueDate, isNull);
      expect(salary.isRecurring, isFalse);
      expect(await ledger.watchIncomeTemplates().first, isEmpty);
    });
  });

  group('cancelIncomeRecurrence', () {
    test('stops the schedule but keeps the original entry', () async {
      final salary = await seedSalary();
      await ledger.cancelIncomeRecurrence(salary);

      final updated = await reload(salary.id);
      expect(updated.isRecurring, isFalse);
      expect(updated.nextDueDate, isNull);
      expect(updated.amount, Money.parse('50000'));
    });
  });

  group('confirmSheetInitialDate', () {
    test('due-or-past occurrence defaults to the scheduled day', () {
      expect(
        confirmSheetInitialDate(
          confirmOccurrence: DateTime(2026, 7, 1),
          existingDate: null,
          now: DateTime(2026, 7, 1),
        ),
        DateTime(2026, 7, 1),
      );
      expect(
        confirmSheetInitialDate(
          confirmOccurrence: DateTime(2026, 7, 1),
          existingDate: null,
          now: DateTime(2026, 7, 5), // logged a few days late
        ),
        DateTime(2026, 7, 1),
      );
    });

    test('a future occurrence (early confirm) defaults to today', () {
      expect(
        confirmSheetInitialDate(
          confirmOccurrence: DateTime(2026, 8, 1),
          existingDate: null,
          now: DateTime(2026, 7, 28), // salary landed early
        ),
        DateTime(2026, 7, 28),
      );
    });

    test('editing an existing entry (no confirm) keeps its own date', () {
      expect(
        confirmSheetInitialDate(
          confirmOccurrence: null,
          existingDate: DateTime(2026, 6, 12),
          now: DateTime(2026, 7, 28),
        ),
        DateTime(2026, 6, 12),
      );
    });
  });

  test('dueIncomeRecurringProvider ordering: oldest due first (via '
      'watchIncomeSeries, which it derives from)', () async {
    await seedSalary(nextDue: DateTime(2026, 8, 1));
    await ledger.addIncome(
      amount: Money.parse('5000'),
      date: DateTime(2026, 6, 1),
      sourceLabel: 'Meal card',
      isRecurring: true,
      recurrence: Recurrence.monthly,
      nextDueDate: DateTime(2026, 7, 1),
    );

    final series = await ledger.watchIncomeSeries(now: DateTime(2026, 9, 1)).first;
    final due = series.where((s) => s.pending.isNotEmpty).toList()
      ..sort((a, b) => a.pending.first.compareTo(b.pending.first));
    expect(due.first.template.sourceLabel, 'Meal card');
  });

  group('addIncomeWithRecurrence', () {
    test('the real entry is never itself flagged recurring', () async {
      final id = await ledger.addIncomeWithRecurrence(
        amount: Money.parse('85000'),
        date: DateTime(2026, 6, 1),
        sourceLabel: 'Salary',
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 7, 1),
      );
      final real = (await ledger.byId(id))!;
      expect(real.isRecurring, isFalse);
      expect(real.templateOnly, isFalse);
    });

    test('a separate template-only row carries the schedule', () async {
      await ledger.addIncomeWithRecurrence(
        amount: Money.parse('85000'),
        date: DateTime(2026, 6, 1),
        sourceLabel: 'Salary',
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 7, 1),
      );
      final all = await ledger.watchIncomeTemplates().first;
      final template = all.single;
      expect(template.templateOnly, isTrue);
      expect(template.nextDueDate, DateTime(2026, 7, 1));
    });

    test('the template-only row is excluded from the income list and total',
        () async {
      await ledger.addIncomeWithRecurrence(
        amount: Money.parse('85000'),
        date: DateTime(2026, 6, 1),
        sourceLabel: 'Salary',
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 7, 1),
      );
      final visible = await ledger.watchAll().first;
      expect(visible, hasLength(1));
      expect(
        await ledger.watchTotalInRange(DateTime(2026, 6, 1), DateTime(2026, 7, 1)).first,
        Money.parse('85000'),
      );
    });
  });

  group('updateIncomeWithRecurrence', () {
    test(
      'turning recurrence on for a plain income entry keeps it plain and '
      'spawns a separate template instead',
      () async {
        final id = await ledger.addIncome(
          amount: Money.parse('85000'),
          date: DateTime(2026, 6, 1),
          sourceLabel: 'Salary',
        );
        await ledger.updateIncomeWithRecurrence(
          id: id,
          amount: Money.parse('85000'),
          date: DateTime(2026, 6, 1),
          sourceLabel: 'Salary',
          recurrence: Recurrence.monthly,
          nextDueDate: DateTime(2026, 7, 1),
        );

        final original = (await ledger.byId(id))!;
        expect(original.isRecurring, isFalse);
        expect(original.templateOnly, isFalse);

        final templates = await ledger.watchIncomeTemplates().first;
        expect(templates, hasLength(1));
      },
    );

    test('editing the spawned template later never touches the original entry',
        () async {
      final id = await ledger.addIncome(
        amount: Money.parse('85000'),
        date: DateTime(2026, 6, 1),
        sourceLabel: 'Salary',
      );
      await ledger.updateIncomeWithRecurrence(
        id: id,
        amount: Money.parse('85000'),
        date: DateTime(2026, 6, 1),
        sourceLabel: 'Salary',
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 7, 1),
      );
      final template = (await ledger.watchIncomeTemplates().first).single;

      // A raise for future months — editing "the rule" directly, exactly
      // like editing any other row.
      await ledger.update(template.id, amount: Money.parse('92000'));

      final original = (await ledger.byId(id))!;
      expect(original.amount, Money.parse('85000'));
    });
  });
}

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/categories/category_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/profile/profile_provider.dart';
import 'package:spendly/features/reports/report_export.dart';
import 'package:spendly/features/reports/report_model.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  Future<Map<int, CategoryRow>> byId() async {
    final cats = await db.select(db.categories).get();
    return {for (final c in cats) c.id: c};
  }

  final start = DateTime(2026, 3, 1);
  final end = DateTime(2026, 3, 11);

  Future<ReportData> build() async {
    final expenses = await repo.listInRange(start, end);
    return buildReport(
      start: start,
      end: end,
      expenses: expenses,
      previousTotal: Money.zero,
      categoriesById: await byId(),
    );
  }

  test('workbook has a Summary sheet and a Transactions sheet', () async {
    final data = await build();
    final bytes = buildXlsx(data, await byId(), title: 'March 2026');
    final wb = xl.Excel.decodeBytes(bytes);
    expect(wb.sheets.keys.toSet(), {'Summary', 'Transactions'});
  });

  test('Transactions sheet: header + one row per expense, exact amount', () async {
    await repo.add(
      amount: Money.parse('24.35'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
    );
    final data = await build();
    final bytes = buildXlsx(data, await byId(), title: 'March 2026');
    final wb = xl.Excel.decodeBytes(bytes);
    final rows = wb['Transactions'].rows;
    expect(rows.length, 2); // header + 1
    expect(
      rows[0].map((c) => (c?.value as xl.TextCellValue?)?.value.text).toList(),
      [
        'Date',
        'Category',
        'Note',
        'Amount',
        'Trip',
        'Account',
        'Payment method',
        'Recurring',
        'Receipt',
        'Paid abroad',
      ],
    );
    expect(rows[1][3]?.value, xl.DoubleCellValue(24.35));
  });

  test(
    'Transactions sheet: trip, account, recurring, receipt and fx columns '
    'are populated when set, blank when not',
    () async {
      final tagId = await db
          .into(db.tags)
          .insert(TagsCompanion.insert(name: 'Japan Trip', colorValue: 0xFF6366F1));
      final accountId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'HDFC Bank', type: AccountType.bank),
          );
      // Fully-loaded row: tagged, accounted, recurring, receipted, foreign.
      final richId = await repo.add(
        amount: Money.parse('4500'),
        categoryId: 1,
        date: DateTime(2026, 3, 3),
        tagId: tagId,
        accountId: accountId,
        isRecurring: true,
        recurrence: Recurrence.monthly,
        nextDueDate: DateTime(2026, 4, 3),
        fxCurrency: 'JPY',
        fxAmount: Money.parse('9000'),
      );
      await db
          .into(db.expenseReceipts)
          .insert(
            ExpenseReceiptsCompanion.insert(
              expenseId: richId,
              photoBytes: Uint8List.fromList([1, 2, 3]),
            ),
          );
      // Bare row: none of the above.
      await repo.add(
        amount: Money.parse('50'),
        categoryId: 1,
        date: DateTime(2026, 3, 4),
      );

      final data = await build();
      final tags = await db.select(db.tags).get();
      final accounts = await db.select(db.accounts).get();
      final bytes = buildXlsx(
        data,
        await byId(),
        title: 'March 2026',
        tagById: {for (final t in tags) t.id: t},
        accountById: {for (final a in accounts) a.id: a},
        expenseIdsWithReceipt: {richId},
      );
      final rows = xl.Excel.decodeBytes(bytes)['Transactions'].rows;
      String cell(int r, int c) =>
          (rows[r][c]?.value as xl.TextCellValue?)?.value.text ?? '';

      // Row 1 (index 1) is the rich one — listInRange orders newest first,
      // and 3/3 is newer than 3/4... actually 3/4 > 3/3, so the bare row
      // (3/4) sorts first. Locate rows by amount instead of assuming order.
      // A whole-number amount round-trips through the xlsx encode/decode as
      // an IntCellValue, not a DoubleCellValue — a quirk of the `excel`
      // package's own type inference, not of buildXlsx. Handle both rather
      // than picking amounts that dodge the quirk.
      double? amountAt(List<xl.Data?> r) {
        final v = r[3]?.value;
        return switch (v) {
          xl.DoubleCellValue() => v.value,
          xl.IntCellValue() => v.value.toDouble(),
          _ => null,
        };
      }

      final richRowIndex = rows.indexWhere((r) => amountAt(r) == 4500.0);
      final bareRowIndex = rows.indexWhere((r) => amountAt(r) == 50.0);

      expect(cell(richRowIndex, 4), 'Japan Trip');
      expect(cell(richRowIndex, 5), 'HDFC Bank');
      expect(cell(richRowIndex, 7), 'Monthly');
      expect(cell(richRowIndex, 8), 'Yes');
      expect(cell(richRowIndex, 9), contains('9,000')); // ¥9,000

      expect(cell(bareRowIndex, 4), '');
      expect(cell(bareRowIndex, 5), '');
      expect(cell(bareRowIndex, 7), '');
      expect(cell(bareRowIndex, 8), '');
      expect(cell(bareRowIndex, 9), '');
    },
  );

  test('Summary sheet: category total matches the report breakdown', () async {
    await repo.add(
      amount: Money.parse('600'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
    );
    await repo.add(
      amount: Money.parse('400'),
      categoryId: 2,
      date: DateTime(2026, 3, 5),
    );
    final cats = await byId();
    final data = await build();
    final bytes = buildXlsx(data, cats, title: 'March 2026');
    final wb = xl.Excel.decodeBytes(bytes);
    final summaryText = wb['Summary'].rows
        .expand((r) => r)
        .map((c) => c?.value)
        .whereType<xl.TextCellValue>()
        .map((v) => v.value.text)
        .toList();
    expect(summaryText, contains(cats[1]!.name));
    expect(summaryText, contains(cats[2]!.name));

    final amounts = wb['Summary'].rows
        .expand((r) => r)
        .map((c) => c?.value)
        .map((v) {
          if (v is xl.DoubleCellValue) return v.value;
          if (v is xl.IntCellValue) return v.value.toDouble();
          return null;
        })
        .whereType<double>()
        .toList();
    expect(amounts, containsAll([600.0, 400.0]));
  });

  test('ignored-for-budget category gets its own "Excluded" section', () async {
    await repo.add(
      amount: Money.parse('600'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
    );
    await CategoryRepository(db).setIgnoredForBudget(1, true);
    final cats = await byId();
    final data = await build();
    final bytes = buildXlsx(data, cats, title: 'March 2026');
    final wb = xl.Excel.decodeBytes(bytes);
    final summaryText = wb['Summary'].rows
        .expand((r) => r)
        .map((c) => c?.value)
        .whereType<xl.TextCellValue>()
        .map((v) => v.value.text ?? '')
        .toList();
    expect(summaryText.any((t) => t.startsWith('Excluded from budget')), isTrue);
    expect(summaryText, contains(cats[1]!.name));
  });

  test('no ignored spend → no "Excluded" section written', () async {
    await repo.add(
      amount: Money.parse('100'),
      categoryId: 1,
      date: DateTime(2026, 3, 2),
    );
    final data = await build();
    final bytes = buildXlsx(data, await byId(), title: 'March 2026');
    final wb = xl.Excel.decodeBytes(bytes);
    final summaryText = wb['Summary'].rows
        .expand((r) => r)
        .map((c) => c?.value)
        .whereType<xl.TextCellValue>()
        .map((v) => v.value.text ?? '');
    expect(summaryText.any((t) => t.startsWith('Excluded from budget')), isFalse);
  });

  test('profile line appears in the Summary footer, blank fields skipped', () async {
    final data = await build();
    final bytes = buildXlsx(
      data,
      await byId(),
      title: 'March 2026',
      profile: const Profile(name: 'Ada', email: '', phone: '99999'),
    );
    final wb = xl.Excel.decodeBytes(bytes);
    final summaryText = wb['Summary'].rows
        .expand((r) => r)
        .map((c) => c?.value)
        .whereType<xl.TextCellValue>()
        .map((v) => v.value.text ?? '')
        .join(' ');
    expect(summaryText, contains('Ada'));
    expect(summaryText, contains('99999'));
  });
}

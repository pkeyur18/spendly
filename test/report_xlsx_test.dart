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
      ['Date', 'Category', 'Note', 'Amount', 'Payment method'],
    );
    expect(rows[1][3]?.value, xl.DoubleCellValue(24.35));
  });

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

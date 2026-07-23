import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/reports/report_export.dart';

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

  test('header + one row per expense', () async {
    await repo.add(amount: Money.parse('10'), categoryId: 1, date: DateTime(2026, 3, 1));
    await repo.add(amount: Money.parse('20'), categoryId: 1, date: DateTime(2026, 3, 2));
    final csv = buildCsv(
        await repo.listInRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1)),
        await byId());
    final lines = csv.split('\r\n');
    expect(lines.first, 'Date,Category,Note,Amount,Payment method');
    expect(lines.length, 3); // header + 2
  });

  test('exact decimal amount, no float', () async {
    await repo.add(amount: Money.parse('24.35'), categoryId: 1, date: DateTime(2026, 3, 1));
    final csv = buildCsv(
        await repo.listInRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1)),
        await byId());
    expect(csv.contains(',24.35,'), isTrue);
  });

  test('fields with comma / quote / newline are RFC-4180 quoted', () async {
    await repo.add(
        amount: Money.parse('5'),
        categoryId: 1,
        date: DateTime(2026, 3, 1),
        note: 'Lunch, "big"\nfeast');
    final csv = buildCsv(
        await repo.listInRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1)),
        await byId());
    // Comma+quote+newline in the note -> whole field quoted, inner quotes doubled.
    expect(csv.contains('"Lunch, ""big""\nfeast"'), isTrue);
  });
}

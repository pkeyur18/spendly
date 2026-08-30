import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/core/db/providers.dart';
import 'package:spendly/core/money/money.dart';
import 'package:spendly/features/accounts/account_repository.dart';
import 'package:spendly/features/expenses/expense_repository.dart';
import 'package:spendly/features/ledger/account_balance_provider.dart';
import 'package:spendly/features/ledger/ledger_repository.dart';

/// `accountBalancesProvider`/`totalBalanceProvider` combine opening balance
/// with four independently-reactive streams (expense/income/transfer-in/
/// transfer-out totals). `balance_math_test.dart` only covers the pure
/// `computeAccountBalance` arithmetic with plain numbers — nothing exercises
/// the actual multi-stream wiring against a real database, which is exactly
/// the class of bug (docs/known-issues.md §1: reactive-read/combination
/// mistakes) this app has shipped before elsewhere.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    // Keep every stream this depends on alive for the test's duration.
    container.listen(totalBalanceProvider, (_, _) {});
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('a single account with only an opening balance', () async {
    await AccountRepository(db).create(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: Money.parse('1000'),
    );

    await _waitUntil(
      container,
      totalBalanceProvider,
      (m) => m == Money.parse('1000'),
    );
  });

  test('income adds, an expense subtracts, on the same account', () async {
    final accountId = await AccountRepository(db).create(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: Money.parse('1000'),
    );
    await LedgerRepository(
      db,
    ).addIncome(amount: Money.parse('500'), date: DateTime.now(), accountId: accountId);
    await ExpenseRepository(db).add(
      amount: Money.parse('200'),
      categoryId: 1,
      date: DateTime.now(),
      accountId: accountId,
    );

    // 1000 + 500 - 200 = 1300
    await _waitUntil(
      container,
      totalBalanceProvider,
      (m) => m == Money.parse('1300'),
    );
  });

  test('a transfer moves balance between two accounts; the total is unchanged',
      () async {
    final accounts = AccountRepository(db);
    final a = await accounts.create(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: Money.parse('1000'),
    );
    final b = await accounts.create(
      name: 'Bank',
      type: AccountType.bank,
      openingBalance: Money.parse('500'),
    );
    await LedgerRepository(db).addTransfer(
      amount: Money.parse('200'),
      date: DateTime.now(),
      fromAccountId: a,
      toAccountId: b,
    );

    // The total (1500) is invariant under a transfer, so waiting on it would
    // resolve before the transfer's own streams have actually propagated —
    // wait on the per-account balances the transfer actually changes.
    await _waitUntil(
      container,
      accountBalancesProvider,
      (m) => m[a] == Money.parse('800') && m[b] == Money.parse('700'),
    );
    expect(container.read(totalBalanceProvider), Money.parse('1500'));
  });

  test('an archived account is excluded from the total, but its balance is '
      'still computed', () async {
    final accounts = AccountRepository(db);
    final active = await accounts.create(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: Money.parse('1000'),
    );
    final archived = await accounts.create(
      name: 'Old Wallet',
      type: AccountType.wallet,
      openingBalance: Money.parse('300'),
    );
    await accounts.setArchived(archived, true);

    await _waitUntil(
      container,
      totalBalanceProvider,
      (m) => m == Money.parse('1000'), // archived account's 300 excluded
    );
    // But accountBalancesProvider (feeds the account's own detail screen)
    // still reports it, unaffected by archived status.
    final balances = container.read(accountBalancesProvider);
    expect(balances[active], Money.parse('1000'));
    expect(balances[archived], Money.parse('300'));
  });

  test('includeInNetWorth: false excludes an active account from the total, '
      'but its own balance is still computed', () async {
    final accounts = AccountRepository(db);
    final counted = await accounts.create(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: Money.parse('1000'),
    );
    final excluded = await accounts.create(
      name: 'Car loan',
      type: AccountType.bank,
      openingBalance: Money.parse('-50000'),
      includeInNetWorth: false,
    );

    await _waitUntil(
      container,
      totalBalanceProvider,
      (m) => m == Money.parse('1000'), // the -50000 liability isn't counted
    );
    final balances = container.read(accountBalancesProvider);
    expect(balances[counted], Money.parse('1000'));
    expect(balances[excluded], Money.parse('-50000'));
  });

  test('an expense with no account attached does not affect any balance',
      () async {
    await AccountRepository(db).create(
      name: 'Cash',
      type: AccountType.cash,
      openingBalance: Money.parse('1000'),
    );
    await ExpenseRepository(
      db,
    ).add(amount: Money.parse('999'), categoryId: 1, date: DateTime.now());
    // accountId left null.

    await _waitUntil(
      container,
      totalBalanceProvider,
      (m) => m == Money.parse('1000'), // unaffected by the unattached expense
    );
  });
}

/// Waits until [provider]'s value satisfies [test], or fails after 5s — same
/// helper shape as `test/widget_test.dart`'s, needed because these providers
/// are only correct once the underlying Drift `.watch()` streams have
/// emitted at least once (ADR-009: no `pumpAndSettle` for stream-backed
/// state).
Future<void> _waitUntil<T>(
  ProviderContainer container,
  Provider<T> provider,
  bool Function(T) test,
) async {
  final done = Completer<void>();
  final sub = container.listen<T>(provider, (_, next) {
    if (!done.isCompleted && test(next)) done.complete();
  }, fireImmediately: true);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

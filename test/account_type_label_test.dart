import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/core/db/database.dart';
import 'package:spendly/features/accounts/accounts_screen.dart';

AccountRow _account({
  required AccountType type,
  String? customTypeName,
}) => AccountRow(
  id: 1,
  name: 'Test',
  type: type,
  openingBalanceMinor: 0,
  openingBalanceMonth: null,
  isArchived: false,
  isDefault: false,
  includeInNetWorth: true,
  isLiability: false,
  customTypeName: customTypeName,
  customTypeIcon: null,
  customTypeColorValue: null,
  isFrequent: false,
  externalId: null,
);

void main() {
  group('accountTypeLabel', () {
    test('a built-in type reads its fixed label', () {
      expect(accountTypeLabel(_account(type: AccountType.bank)), 'Bank');
    });

    test("a custom account reads its own name, not a generic 'Custom'", () {
      final account = _account(
        type: AccountType.custom,
        customTypeName: 'Loan',
      );
      expect(accountTypeLabel(account), 'Loan');
    });

    test('a custom account with no name set falls back to Custom', () {
      final account = _account(type: AccountType.custom, customTypeName: null);
      expect(accountTypeLabel(account), 'Custom');
    });

    test('a custom account with a blank name falls back to Custom', () {
      final account = _account(type: AccountType.custom, customTypeName: '');
      expect(accountTypeLabel(account), 'Custom');
    });
  });
}

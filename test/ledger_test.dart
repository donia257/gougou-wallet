import 'dart:convert';
import 'package:daily_ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerEntry entry(
  String id,
  EntryType type,
  int cents, {
  String? destination,
}) => LedgerEntry(
  id: id,
  type: type,
  cents: cents,
  date: DateTime(2026, 11, 6),
  category: type == EntryType.income
      ? 'income-0'
      : type == EntryType.transfer
      ? 'transfer'
      : 'expense-0',
  accountId: 'cash',
  toAccountId: destination,
);

void main() {
  test(
    'daily allowance handles month end, leap years, future months and overspending',
    () {
      expect(
        budgetDaysRemaining(DateTime(2026, 11), DateTime(2026, 11, 8)),
        23,
      );
      expect(dailyDisposableCents(100000, 25000, 23), 3260);
      expect(
        budgetDaysRemaining(DateTime(2026, 11), DateTime(2026, 11, 30)),
        1,
      );
      expect(budgetDaysRemaining(DateTime(2026, 10), DateTime(2026, 11, 8)), 0);
      expect(budgetDaysRemaining(DateTime(2028, 2), DateTime(2027, 12, 8)), 29);
      expect(dailyDisposableCents(10000, 11000, 5), 0);
      expect(dailyDisposableCents(10000, 10000, 5), 0);
      expect(dailyDisposableCents(10000, 0, 0), 0);
    },
  );

  test(
    'money uses integer cents and rejects malformed or excessive precision',
    () {
      expect(parseMoney('0.01'), 1);
      expect(parseMoney('12.3'), 1230);
      expect(parseMoney('999999999.99'), 99999999999);
      for (final invalid in [
        '1.001',
        '-1',
        '1e3',
        'NaN',
        '',
        '1..2',
        '1000000000',
      ]) {
        expect(() => parseMoney(invalid), throwsFormatException);
      }
    },
  );

  test(
    'transfer balances both accounts without inflating income or spending',
    () {
      final ledger = Ledger.empty().copyWith(
        entries: [
          entry('income', EntryType.income, 10000),
          entry('food', EntryType.expense, 1200),
          entry('transfer', EntryType.transfer, 3000, destination: 'wechat'),
        ],
      );
      ledger.validate();
      expect(ledger.balance('cash'), 5800);
      expect(ledger.balance('wechat'), 3000);
      expect(ledger.total(EntryType.income, DateTime(2026, 11)), 10000);
      expect(ledger.total(EntryType.expense, DateTime(2026, 11)), 1200);
      expect(ledger.total(EntryType.expense, DateTime(2026, 12)), 0);
      final deleted = ledger.copyWith(
        entries: ledger.entries.where((e) => e.id != 'transfer').toList(),
      );
      expect(deleted.balance('cash'), 8800);
      expect(deleted.balance('wechat'), 0);
    },
  );

  test(
    'backup round trip retains opening balances, categories, budgets and entries',
    () {
      final ledger = Ledger.empty().copyWith(
        accounts: const [
          Account('cash', '现金', -1234),
          Account('wechat', '微信', 20000),
        ],
        entries: [entry('test', EntryType.expense, 12)],
        budgets: {'2026-11': 50000},
      );
      final restored = Ledger.decode(ledger.encode());
      expect(restored.encode(), ledger.encode());
      expect(restored.balance('cash'), -1246);
    },
  );

  test(
    'backup validation rejects orphaned, duplicate and invalid transfers',
    () {
      for (final entries in [
        [entry('test', EntryType.transfer, 10, destination: 'missing')],
        [entry('test', EntryType.transfer, 10, destination: 'cash')],
        [entry('test', EntryType.expense, 0)],
        [
          entry('test', EntryType.expense, 10),
          entry('test', EntryType.expense, 20),
        ],
      ]) {
        expect(
          () =>
              Ledger.decode(Ledger.empty().copyWith(entries: entries).encode()),
          throwsFormatException,
        );
      }
      final json = Ledger.empty().toJson()..['version'] = 99;
      expect(() => Ledger.decode(jsonEncode(json)), throwsFormatException);
    },
  );
}

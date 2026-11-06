import 'dart:convert';

enum EntryType { expense, income, transfer }

int parseMoney(String text) {
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(text.trim())) {
    throw const FormatException('请输入有效金额，最多保留两位小数');
  }
  final parts = text.trim().split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

String money(int cents) => (cents / 100).toStringAsFixed(2);
String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';
String dayLabel(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

class Account {
  const Account(this.id, this.name, this.openingCents);
  final String id;
  final String name;
  final int openingCents;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'openingCents': openingCents,
  };
  factory Account.fromJson(Map<String, dynamic> json) => Account(
    json['id'] as String,
    json['name'] as String,
    json['openingCents'] as int,
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.cents,
    required this.date,
    required this.category,
    required this.accountId,
    this.toAccountId,
    this.note = '',
  });
  final String id;
  final EntryType type;
  final int cents;
  final DateTime date;
  final String category;
  final String accountId;
  final String? toAccountId;
  final String note;
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'cents': cents,
    'date': date.toIso8601String(),
    'category': category,
    'accountId': accountId,
    'toAccountId': toAccountId,
    'note': note,
  };
  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as String,
    type: EntryType.values.byName(json['type'] as String),
    cents: json['cents'] as int,
    date: DateTime.parse(json['date'] as String),
    category: json['category'] as String,
    accountId: json['accountId'] as String,
    toAccountId: json['toAccountId'] as String?,
    note: json['note'] as String,
  );
}

class Ledger {
  Ledger({
    required List<Account> accounts,
    required List<LedgerEntry> entries,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
    required Map<String, int> budgets,
  }) : accounts = List.unmodifiable(accounts),
       entries = List.unmodifiable(entries),
       expenseCategories = List.unmodifiable(expenseCategories),
       incomeCategories = List.unmodifiable(incomeCategories),
       budgets = Map.unmodifiable(budgets);

  factory Ledger.empty() => Ledger(
    accounts: const [
      Account('cash', '现金', 0),
      Account('wechat', '微信', 0),
      Account('alipay', '支付宝', 0),
      Account('bank', '银行卡', 0),
    ],
    entries: [],
    expenseCategories: ['餐饮', '购物', '交通', '日用', '住房', '娱乐', '医疗', '学习', '其他'],
    incomeCategories: ['工资', '奖金', '红包', '兼职', '其他收入'],
    budgets: {},
  );

  final List<Account> accounts;
  final List<LedgerEntry> entries;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final Map<String, int> budgets;

  Ledger copyWith({
    List<Account>? accounts,
    List<LedgerEntry>? entries,
    List<String>? expenseCategories,
    List<String>? incomeCategories,
    Map<String, int>? budgets,
  }) => Ledger(
    accounts: accounts ?? this.accounts,
    entries: entries ?? this.entries,
    expenseCategories: expenseCategories ?? this.expenseCategories,
    incomeCategories: incomeCategories ?? this.incomeCategories,
    budgets: budgets ?? this.budgets,
  );

  int total(EntryType type, DateTime month) => entries
      .where((e) => e.type == type && monthKey(e.date) == monthKey(month))
      .fold(0, (sum, e) => sum + e.cents);

  int balance(String accountId) {
    var result = accounts.firstWhere((a) => a.id == accountId).openingCents;
    for (final entry in entries) {
      if (entry.accountId == accountId) {
        result += entry.type == EntryType.income ? entry.cents : -entry.cents;
      }
      if (entry.type == EntryType.transfer && entry.toAccountId == accountId) {
        result += entry.cents;
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'expenseCategories': expenseCategories,
    'incomeCategories': incomeCategories,
    'budgets': budgets,
  };

  String encode() => jsonEncode(toJson());

  factory Ledger.decode(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('不支持此备份版本');
    final ledger = Ledger(
      accounts: (data['accounts'] as List)
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList(),
      entries: (data['entries'] as List)
          .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      expenseCategories: List<String>.from(data['expenseCategories'] as List),
      incomeCategories: List<String>.from(data['incomeCategories'] as List),
      budgets: Map<String, int>.from(data['budgets'] as Map),
    );
    ledger.validate();
    return ledger;
  }

  void validate() {
    final ids = accounts.map((a) => a.id).toSet();
    if (accounts.isEmpty ||
        ids.length != accounts.length ||
        accounts.any(
          (a) =>
              a.id.isEmpty ||
              a.name.trim().isEmpty ||
              a.openingCents.abs() > 99999999999,
        ) ||
        entries.map((e) => e.id).toSet().length != entries.length ||
        expenseCategories.isEmpty ||
        incomeCategories.isEmpty ||
        [
          ...expenseCategories,
          ...incomeCategories,
        ].any((c) => c.trim().isEmpty) ||
        expenseCategories.toSet().length != expenseCategories.length ||
        incomeCategories.toSet().length != incomeCategories.length ||
        budgets.entries.any(
          (b) =>
              !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(b.key) ||
              b.value <= 0 ||
              b.value > 99999999999,
        )) {
      throw const FormatException('账本数据不完整或格式有误');
    }
    for (final entry in entries) {
      if (entry.id.isEmpty ||
          entry.cents <= 0 ||
          entry.cents > 99999999999 ||
          !ids.contains(entry.accountId) ||
          entry.date.year < 1900 ||
          entry.date.year > 2100 ||
          (entry.type == EntryType.transfer &&
              (!ids.contains(entry.toAccountId) ||
                  entry.accountId == entry.toAccountId)) ||
          (entry.type != EntryType.transfer && entry.toAccountId != null) ||
          (entry.type == EntryType.expense &&
              !expenseCategories.contains(entry.category)) ||
          (entry.type == EntryType.income &&
              !incomeCategories.contains(entry.category))) {
        throw const FormatException('账单金额、分类、日期或关联账户有误');
      }
    }
  }
}

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
String monthKey(DateTime date) => '${date.year}-${twoDigits(date.month)}';
String twoDigits(int value) => value.toString().padLeft(2, '0');
String dayKey(DateTime date) => '${monthKey(date)}-${twoDigits(date.day)}';
String dayLabel(DateTime date) => '${date.month} 月 ${date.day} 日';
String timeLabel(DateTime date) =>
    '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);

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

class LedgerCategory {
  const LedgerCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
  });
  final String id;
  final String name;
  final EntryType type;
  final String icon;
  LedgerCategory copyWith({String? name, String? icon}) => LedgerCategory(
    id: id,
    name: name ?? this.name,
    type: type,
    icon: icon ?? this.icon,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'icon': icon,
  };
  factory LedgerCategory.fromJson(Map<String, dynamic> json) => LedgerCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    type: EntryType.values.byName(json['type'] as String),
    icon: json['icon'] as String? ?? '其他',
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
  // Version 2 uses a stable category ID. Version 1 names are mapped on import.
  final String category;
  final String accountId;
  final String? toAccountId;
  final String note;
  LedgerEntry copyWith({String? id, DateTime? date, String? category}) =>
      LedgerEntry(
        id: id ?? this.id,
        type: type,
        cents: cents,
        date: date ?? this.date,
        category: category ?? this.category,
        accountId: accountId,
        toAccountId: toAccountId,
        note: note,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'cents': cents,
    'date': date.toIso8601String(),
    'categoryId': category,
    'accountId': accountId,
    'toAccountId': toAccountId,
    'note': note,
  };
  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final dateText = json['date'] as String;
    final components = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(dateText);
    if (components == null) throw const FormatException('账单日期格式有误');
    final values = List.generate(6, (i) => int.parse(components.group(i + 1)!));
    final day = DateTime(values[0], values[1], values[2]);
    if (day.year != values[0] ||
        day.month != values[1] ||
        day.day != values[2] ||
        values[3] > 23 ||
        values[4] > 59 ||
        values[5] > 59) {
      throw const FormatException('账单日期或时间有误');
    }
    return LedgerEntry(
      id: json['id'] as String,
      type: EntryType.values.byName(json['type'] as String),
      cents: json['cents'] as int,
      date: DateTime.parse(dateText),
      category: json['categoryId'] as String,
      accountId: json['accountId'] as String,
      toAccountId: json['toAccountId'] as String?,
      note: json['note'] as String? ?? '',
    );
  }
}

class Ledger {
  Ledger({
    required List<Account> accounts,
    required List<LedgerEntry> entries,
    required List<LedgerCategory> categories,
    required Map<String, int> budgets,
    String? lastAccountId,
  }) : accounts = List.unmodifiable(accounts),
       entries = List.unmodifiable(entries),
       categories = List.unmodifiable(categories),
       budgets = Map.unmodifiable(budgets),
       lastAccountId = lastAccountId ?? accounts.first.id;

  factory Ledger.empty() {
    const expenses = ['餐饮', '购物', '交通', '日用', '住房', '娱乐', '医疗', '学习', '其他'];
    const incomes = ['工资', '奖金', '红包', '兼职', '其他收入'];
    return Ledger(
      accounts: const [
        Account('cash', '现金', 0),
        Account('wechat', '微信', 0),
        Account('alipay', '支付宝', 0),
        Account('bank', '银行卡', 0),
      ],
      entries: [],
      budgets: {},
      categories: [
        for (var i = 0; i < expenses.length; i++)
          LedgerCategory(
            id: 'expense-$i',
            name: expenses[i],
            type: EntryType.expense,
            icon: expenses[i],
          ),
        for (var i = 0; i < incomes.length; i++)
          LedgerCategory(
            id: 'income-$i',
            name: incomes[i],
            type: EntryType.income,
            icon: incomes[i],
          ),
      ],
    );
  }
  final List<Account> accounts;
  final List<LedgerEntry> entries;
  final List<LedgerCategory> categories;
  final Map<String, int> budgets;
  final String lastAccountId;

  Ledger copyWith({
    List<Account>? accounts,
    List<LedgerEntry>? entries,
    List<LedgerCategory>? categories,
    Map<String, int>? budgets,
    String? lastAccountId,
  }) => Ledger(
    accounts: accounts ?? this.accounts,
    entries: entries ?? this.entries,
    categories: categories ?? this.categories,
    budgets: budgets ?? this.budgets,
    lastAccountId: lastAccountId ?? this.lastAccountId,
  );

  List<LedgerCategory> categoriesFor(EntryType type) =>
      categories.where((c) => c.type == type).toList();
  LedgerCategory categoryById(String id) =>
      categories.firstWhere((c) => c.id == id);
  String categoryName(LedgerEntry entry) => entry.type == EntryType.transfer
      ? '转账'
      : categoryById(entry.category).name;
  String accountName(String id) => accounts.firstWhere((a) => a.id == id).name;
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

  List<LedgerEntry> selectEntries({
    required DateTime start,
    required DateTime end,
    EntryType? type,
    String? accountId,
    String? categoryId,
    String query = '',
  }) {
    final first = dayKey(start);
    final last = dayKey(end);
    final search = query.trim().toLowerCase();
    final categoryNames = {for (final c in categories) c.id: c.name};
    final accountNames = {for (final a in accounts) a.id: a.name};
    final result = entries
        .where(
          (e) =>
              dayKey(e.date).compareTo(first) >= 0 &&
              dayKey(e.date).compareTo(last) <= 0 &&
              (type == null || e.type == type) &&
              (accountId == null ||
                  e.accountId == accountId ||
                  e.toAccountId == accountId) &&
              (categoryId == null || e.category == categoryId) &&
              '${e.note} ${categoryNames[e.category] ?? '转账'} ${accountNames[e.accountId]} ${accountNames[e.toAccountId] ?? ''}'
                  .toLowerCase()
                  .contains(search),
        )
        .toList();
    result.sort((a, b) {
      final dates = b.date.toIso8601String().compareTo(
        a.date.toIso8601String(),
      );
      return dates == 0 ? b.id.compareTo(a.id) : dates;
    });
    return result;
  }

  Ledger removeCategory(String id, {String? replacementId}) {
    final category = categoryById(id);
    if (categoriesFor(category.type).length <= 1) {
      throw const FormatException('每种收支至少保留一个分类');
    }
    final used = entries.any(
      (e) => e.type != EntryType.transfer && e.category == id,
    );
    if (used) {
      final replacement = categories.where(
        (c) => c.id == replacementId && c.id != id && c.type == category.type,
      );
      if (replacement.isEmpty) throw const FormatException('请选择同类型的账单迁移分类');
    }
    return copyWith(
      categories: categories.where((c) => c.id != id).toList(),
      entries: entries
          .map(
            (e) => e.type != EntryType.transfer && e.category == id
                ? e.copyWith(category: replacementId!)
                : e,
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'budgets': budgets,
    'lastAccountId': lastAccountId,
  };
  String encode() => jsonEncode(toJson());

  factory Ledger.decode(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (data['version'] == 1) {
      final categories = <LedgerCategory>[];
      for (final type in [EntryType.expense, EntryType.income]) {
        final names = List<String>.from(
          data[type == EntryType.expense
                  ? 'expenseCategories'
                  : 'incomeCategories']
              as List,
        );
        for (var i = 0; i < names.length; i++) {
          categories.add(
            LedgerCategory(
              id: '${type.name}-$i',
              name: names[i],
              type: type,
              icon: names[i],
            ),
          );
        }
      }
      data['categories'] = categories.map((c) => c.toJson()).toList();
      data['entries'] = (data['entries'] as List).map((value) {
        final entry = Map<String, dynamic>.from(value as Map);
        entry['categoryId'] = entry['type'] == 'transfer'
            ? 'transfer'
            : categories
                  .firstWhere(
                    (c) =>
                        c.name == entry['category'] &&
                        c.type.name == entry['type'],
                    orElse: () => throw const FormatException('旧账单关联的分类不存在'),
                  )
                  .id;
        return entry;
      }).toList();
    } else if (data['version'] != 2) {
      throw const FormatException('不支持此备份版本');
    }
    final accounts = (data['accounts'] as List)
        .map((a) => Account.fromJson(a as Map<String, dynamic>))
        .toList();
    if (accounts.isEmpty) throw const FormatException('账本缺少账户数据');
    final ledger = Ledger(
      accounts: accounts,
      entries: (data['entries'] as List)
          .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      categories: (data['categories'] as List)
          .map((c) => LedgerCategory.fromJson(c as Map<String, dynamic>))
          .toList(),
      budgets: Map<String, int>.from(data['budgets'] as Map),
      lastAccountId: data['lastAccountId'] as String?,
    );
    ledger.validate();
    return ledger;
  }

  void validate() {
    final ids = accounts.map((a) => a.id).toSet();
    final categoryMap = {for (final c in categories) c.id: c};
    if (accounts.isEmpty ||
        ids.length != accounts.length ||
        !ids.contains(lastAccountId) ||
        accounts.any(
          (a) =>
              a.id.isEmpty ||
              a.name.trim().isEmpty ||
              a.openingCents.abs() > 99999999999,
        ) ||
        categoryMap.length != categories.length ||
        categories.any(
          (c) =>
              c.id.isEmpty ||
              c.name.trim().isEmpty ||
              c.type == EntryType.transfer,
        ) ||
        categoriesFor(EntryType.expense).isEmpty ||
        categoriesFor(EntryType.income).isEmpty ||
        categoriesFor(EntryType.expense).map((c) => c.name).toSet().length !=
            categoriesFor(EntryType.expense).length ||
        categoriesFor(EntryType.income).map((c) => c.name).toSet().length !=
            categoriesFor(EntryType.income).length ||
        entries.map((e) => e.id).toSet().length != entries.length ||
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
          (entry.type != EntryType.transfer &&
              (entry.toAccountId != null ||
                  categoryMap[entry.category]?.type != entry.type))) {
        throw const FormatException('账单金额、分类、日期或关联账户有误');
      }
    }
  }
}

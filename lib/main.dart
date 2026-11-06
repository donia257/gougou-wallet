import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'ledger.dart';
import 'repository.dart';

const forest = Color(0xFF245748);
const paper = Color(0xFFF6F5EF);
const ink = Color(0xFF263C34);
const muted = Color(0xFF7A857E);
const coral = Color(0xFFC86C50);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailyApp());
}

class DailyApp extends StatelessWidget {
  const DailyApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '汪汪钱包',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: forest, surface: paper),
      fontFamily: 'DailySans',
      fontFamilyFallback: const ['DailyChinese'],
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: forest,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: home ?? const LedgerHome(),
  );
}

IconData categoryIcon(String name) => switch (name) {
  '餐饮' => Icons.ramen_dining_rounded,
  '交通' => Icons.directions_bus_rounded,
  '购物' => Icons.shopping_bag_outlined,
  '日用' => Icons.local_florist_outlined,
  '住房' => Icons.home_outlined,
  '娱乐' => Icons.sports_esports_outlined,
  '医疗' => Icons.health_and_safety_outlined,
  '学习' => Icons.menu_book_rounded,
  '工资' || '奖金' => Icons.work_outline_rounded,
  '红包' => Icons.redeem_rounded,
  '转账' => Icons.swap_horiz_rounded,
  _ => Icons.grid_view_rounded,
};

class LedgerHome extends StatefulWidget {
  const LedgerHome({super.key, this.repository});
  final LedgerRepository? repository;
  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  late final repository = widget.repository ?? LedgerRepository();
  Ledger? ledger;
  Object? loadError;
  bool busy = false;
  int page = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String query = '';
  EntryType? filter;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loadError = null);
    try {
      final loaded = await repository.open();
      if (mounted) setState(() => ledger = loaded);
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> commit(Ledger next) async {
    if (busy) return false;
    setState(() => busy = true);
    try {
      await repository.save(next);
      if (mounted) setState(() => ledger = next);
      return true;
    } catch (error) {
      message('保存失败，原有账本已保留。请检查存储空间后重试。');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> input(
    String title, {
    String initial = '',
    bool numeric = false,
    String? hint,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: numeric ? 12 : 24,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog exit animations can still reference its controller for one frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return result;
  }

  Future<void> editEntry([LedgerEntry? entry]) async {
    if (busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EntryEditor(
          ledger: ledger!,
          entry: entry,
          onSave: (value) async {
            final saved = await commit(
              ledger!.copyWith(
                entries: [
                  ...ledger!.entries.where((e) => e.id != value.id),
                  value,
                ],
              ),
            );
            if (saved) message(entry == null ? '已记下这一笔' : '账单已更新');
            return saved;
          },
          onDelete: entry == null
              ? null
              : () async {
                  if (!await confirm('删除这笔账单？', '删除后会同步重新计算账户余额、统计和预算。')) {
                    return false;
                  }
                  return commit(
                    ledger!.copyWith(
                      entries: ledger!.entries
                          .where((e) => e.id != entry.id)
                          .toList(),
                    ),
                  );
                },
        ),
      ),
    );
  }

  Future<void> setBudget() async {
    final current = ledger!.budgets[monthKey(month)];
    final text = await input(
      '${month.month} 月生活预算',
      initial: current == null ? '' : money(current),
      numeric: true,
      hint: '输入金额，留空可移除预算',
    );
    if (text == null || !mounted) return;
    try {
      final budgets = Map<String, int>.from(ledger!.budgets);
      if (text.isEmpty) {
        budgets.remove(monthKey(month));
      } else {
        final amount = parseMoney(text);
        if (amount <= 0) throw const FormatException('预算应大于零');
        budgets[monthKey(month)] = amount;
      }
      await commit(ledger!.copyWith(budgets: budgets));
    } on FormatException catch (error) {
      message(error.message);
    }
  }

  Future<void> addAccount([Account? existing]) async {
    final name = await input(
      existing == null ? '添加账户' : '编辑账户',
      initial: existing?.name ?? '',
      hint: '例如：工资卡',
    );
    if (name == null || !mounted) return;
    if (name.isEmpty ||
        ledger!.accounts.any((a) => a.name == name && a.id != existing?.id)) {
      message('请输入一个未使用的账户名称');
      return;
    }
    final opening = await input(
      '记账前的初始余额',
      initial: money(existing?.openingCents ?? 0),
      numeric: true,
      hint: '可用负数记录负债',
    );
    if (opening == null || !mounted) return;
    try {
      final negative = opening.startsWith('-');
      final cents = parseMoney(negative ? opening.substring(1) : opening);
      final account = Account(
        existing?.id ?? 'a${DateTime.now().microsecondsSinceEpoch}',
        name,
        negative ? -cents : cents,
      );
      await commit(
        ledger!.copyWith(
          accounts: existing == null
              ? [...ledger!.accounts, account]
              : ledger!.accounts
                    .map((a) => a.id == existing.id ? account : a)
                    .toList(),
        ),
      );
    } on FormatException catch (error) {
      message(error.message);
    }
  }

  Future<void> addCategory(bool income) async {
    final name = await input(income ? '新增收入分类' : '新增支出分类');
    if (name == null || !mounted) return;
    final categories = income
        ? ledger!.incomeCategories
        : ledger!.expenseCategories;
    if (name.isEmpty || categories.contains(name)) {
      message('请输入一个未使用的分类名称');
      return;
    }
    await commit(
      income
          ? ledger!.copyWith(incomeCategories: [...categories, name])
          : ledger!.copyWith(expenseCategories: [...categories, name]),
    );
  }

  Future<void> exportBackup() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存账本备份',
        fileName: '汪汪钱包-${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(ledger!.encode())),
      );
      if (result != null) message('备份已保存，文件包含完整账本，请妥善保管');
    } catch (error) {
      message('备份导出失败，请重试并选择可写入的位置');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importBackup() async {
    if (busy) return;
    setState(() => busy = true);
    Ledger? imported;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null) return;
      final file = result.files.single;
      if (file.size > 20 * 1024 * 1024) {
        throw const FormatException('备份文件超过 20 MB');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      imported = Ledger.decode(utf8.decode(bytes));
    } catch (error) {
      message('无法读取备份，请选择汪汪钱包导出的有效 JSON 文件');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (imported == null || !mounted) return;
    if (await confirm(
      '恢复这份备份？',
      '备份包含 ${imported.accounts.length} 个账户、${imported.entries.length} 笔账单。'
          '\n\n这会替换当前全部数据。建议先导出当前账本备份。',
    )) {
      if (await commit(imported)) message('账本已恢复');
    }
  }

  List<LedgerEntry> get monthlyEntries {
    final result = ledger!.entries
        .where((e) => monthKey(e.date) == monthKey(month))
        .toList();
    result.sort((a, b) {
      final dates = b.date.compareTo(a.date);
      return dates == 0 ? b.id.compareTo(a.id) : dates;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (ledger == null) {
      return Scaffold(
        body: Center(
          child: loadError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.storage_rounded,
                        size: 48,
                        color: forest,
                      ),
                      const SizedBox(height: 16),
                      const Text('账本暂时无法打开'),
                      const SizedBox(height: 8),
                      const Text('请检查设备存储空间后重试。', textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      FilledButton(onPressed: load, child: const Text('重新打开')),
                    ],
                  ),
                ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 100),
                children: [
                  header(),
                  const SizedBox(height: 26),
                  ...switch (page) {
                    0 => homeContent(),
                    1 => billContent(),
                    2 => statsContent(),
                    _ => accountContent(),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : () => editEntry(),
        backgroundColor: forest,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('记一笔'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) => setState(() => page = value),
        backgroundColor: paper,
        indicatorColor: const Color(0xFFDDE7D7),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.cottage_outlined),
            selectedIcon: Icon(Icons.cottage_rounded),
            label: '日常',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: '账单',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_small_outlined),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: '我的',
          ),
        ],
      ),
    );
  }

  Widget header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WANGWANG / 汪汪钱包',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          if (page != 3)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '上个月',
                    icon: const Icon(Icons.chevron_left, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 48,
                    ),
                    onPressed: month.year == 1900 && month.month == 1
                        ? null
                        : () => setState(
                            () => month = DateTime(month.year, month.month - 1),
                          ),
                  ),
                  Text(
                    '${month.year}\n${month.month} 月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: forest,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    icon: const Icon(Icons.chevron_right, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 48,
                    ),
                    onPressed: month.year == 2100 && month.month == 12
                        ? null
                        : () => setState(
                            () => month = DateTime(month.year, month.month + 1),
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        ['把日子，慢慢记好。', '每一笔，都有迹可循。', '看见生活的去向。', '自己的账，安心存。'][page],
        style: const TextStyle(
          fontSize: 25,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    ],
  );

  List<Widget> homeContent() {
    final expense = ledger!.total(EntryType.expense, month);
    final income = ledger!.total(EntryType.income, month);
    return [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: forest,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    '这个月，花了多少',
                    style: TextStyle(color: Color(0xFFD9E7CD), fontSize: 13),
                  ),
                ),
                Icon(Icons.spa_outlined, color: Color(0xFFD9E7CD), size: 22),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '¥ ${money(expense)}',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(color: Color(0xFF55796A), height: 1),
            ),
            Row(
              children: [
                Expanded(child: summary('月收入', income)),
                Expanded(child: summary('月结余', income - expense)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      budgetCard(),
      const SizedBox(height: 26),
      sectionTitle(
        '最近的生活',
        action: '查看全部',
        onTap: () => setState(() => page = 1),
      ),
      const SizedBox(height: 12),
      if (monthlyEntries.isEmpty)
        emptyState('从今天的第一笔开始', '一顿早餐，一次出行，都值得被认真记录。')
      else
        panel(Column(children: monthlyEntries.take(6).map(entryTile).toList())),
      const SizedBox(height: 16),
      const Text(
        '仅存本机 · 无需注册 · 离线可用',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: muted),
      ),
    ];
  }

  Widget summary(String label, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFFD9E7CD), fontSize: 12),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '¥ ${money(value)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  Widget budgetCard() {
    final budget = ledger!.budgets[monthKey(month)];
    final expense = ledger!.total(EntryType.expense, month);
    return panel(
      InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: busy ? null : setBudget,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.track_changes_rounded,
                    color: forest,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '生活预算',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    budget == null ? '去设置 ›' : '调整 ›',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (budget == null)
                const Text(
                  '给这个月的生活，留一点计划。',
                  style: TextStyle(color: muted, fontSize: 12),
                )
              else ...[
                LinearProgressIndicator(
                  value: (expense / budget).clamp(0.0, 1.0),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(8),
                  color: expense > budget ? coral : forest,
                  backgroundColor: paper,
                ),
                const SizedBox(height: 12),
                Text(
                  '${expense > budget ? '已超出' : '还可用'} ¥ ${money((budget - expense).abs())}  /  预算 ¥ ${money(budget)}',
                  style: TextStyle(
                    color: expense > budget ? coral : muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> billContent() {
    final entries = monthlyEntries
        .where(
          (e) =>
              (filter == null || e.type == filter) &&
              '${e.note} ${e.category} ${accountName(e.accountId)}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return [
      TextField(
        decoration: const InputDecoration(
          hintText: '搜索备注、分类或账户',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        onChanged: (value) => setState(() => query = value),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          filterChip('全部', null),
          filterChip('支出', EntryType.expense),
          filterChip('收入', EntryType.income),
          filterChip('转账', EntryType.transfer),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        '共 ${entries.length} 笔',
        style: const TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      if (entries.isEmpty)
        emptyState('这里还没有账单', '换个月份或筛选条件，或者记下新的一笔。')
      else
        panel(Column(children: entries.map(entryTile).toList())),
    ];
  }

  Widget filterChip(String label, EntryType? value) => ChoiceChip(
    label: Text(label),
    selected: filter == value,
    onSelected: (_) => setState(() => filter = value),
  );

  List<Widget> statsContent() {
    final total = ledger!.total(EntryType.expense, month);
    final totals = <String, int>{};
    for (final entry in monthlyEntries.where(
      (e) => e.type == EntryType.expense,
    )) {
      totals.update(
        entry.category,
        (value) => value + entry.cents,
        ifAbsent: () => entry.cents,
      );
    }
    final ranking = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final days = monthlyEntries
        .where((e) => e.type == EntryType.expense)
        .map((e) => '${e.date.year}-${e.date.month}-${e.date.day}')
        .toSet()
        .length;
    return [
      panel(
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(child: statNumber('本月支出', '¥ ${money(total)}')),
              Expanded(child: statNumber('有支出的日子', '$days 天')),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      sectionTitle('钱花在了哪里'),
      const SizedBox(height: 12),
      if (ranking.isEmpty)
        emptyState('等生活积累一点', '记下支出后，这里会展示分类占比与排行。')
      else
        panel(
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: ranking
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                categoryIcon(item.key),
                                color: forest,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(item.key)),
                              Text(
                                '¥ ${money(item.value)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${(item.value * 100 / total).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: item.value / total,
                            color: forest,
                            backgroundColor: paper,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      const SizedBox(height: 24),
      budgetCard(),
      const SizedBox(height: 12),
      const Text(
        '账户间转账不计入收入、支出和预算。',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ];
  }

  Widget statNumber(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 10),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: forest,
          ),
        ),
      ),
    ],
  );

  List<Widget> accountContent() {
    final total = ledger!.accounts.fold(
      0,
      (sum, a) => sum + ledger!.balance(a.id),
    );
    return [
      panel(
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/brand/wangwang-wallet-logo.png',
                      width: 48,
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '汪汪钱包',
                    style: TextStyle(
                      fontSize: 20,
                      color: forest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              statNumber('账户总余额', '¥ ${money(total)}'),
              const SizedBox(height: 8),
              const Text(
                '人民币 CNY · 包含初始余额和全部历史账单',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      sectionTitle('我的账户', action: '添加', onTap: busy ? null : addAccount),
      const SizedBox(height: 10),
      panel(
        Column(
          children: ledger!.accounts
              .map(
                (a) => ListTile(
                  leading: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: forest,
                  ),
                  title: Text(a.name),
                  subtitle: const Text(
                    '点击编辑名称和初始余额',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  onTap: busy ? null : () => addAccount(a),
                  trailing: Text(
                    '¥ ${money(ledger!.balance(a.id))}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 24),
      sectionTitle('分类管理'),
      const SizedBox(height: 10),
      panel(
        Column(
          children: [
            ListTile(
              title: const Text('支出分类'),
              subtitle: Text(ledger!.expenseCategories.join(' · ')),
              trailing: IconButton(
                tooltip: '新增支出分类',
                icon: const Icon(Icons.add),
                onPressed: busy ? null : () => addCategory(false),
              ),
            ),
            ListTile(
              title: const Text('收入分类'),
              subtitle: Text(ledger!.incomeCategories.join(' · ')),
              trailing: IconButton(
                tooltip: '新增收入分类',
                icon: const Icon(Icons.add),
                onPressed: busy ? null : () => addCategory(true),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      sectionTitle('数据与备份'),
      const SizedBox(height: 10),
      panel(
        Column(
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined, color: forest),
              title: const Text('导出本地备份'),
              subtitle: const Text('保存完整账本 JSON 文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : exportBackup,
            ),
            ListTile(
              leading: const Icon(Icons.restore_rounded, color: forest),
              title: const Text('从备份恢复'),
              subtitle: const Text('恢复前会提示确认替换现有账本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : importBackup,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        '账本保存在这台手机上。卸载应用或清除应用数据会删除本地账本，请定期导出备份。备份为明文文件。',
        style: TextStyle(color: muted, height: 1.7, fontSize: 12),
      ),
      const SizedBox(height: 20),
      const Center(
        child: Text(
          '汪汪钱包  0.1.0',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ),
    ];
  }

  String accountName(String id) =>
      ledger!.accounts.firstWhere((a) => a.id == id).name;

  Widget entryTile(LedgerEntry entry) {
    final income = entry.type == EntryType.income;
    final transfer = entry.type == EntryType.transfer;
    final label = transfer ? '转账' : entry.category;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: income ? const Color(0xFFE5EDDF) : const Color(0xFFF4EDE1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(categoryIcon(label), color: forest, size: 23),
      ),
      title: Text(
        entry.note.isEmpty ? label : entry.note,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${dayLabel(entry.date)} · $label · ${accountName(entry.accountId)}'
        '${transfer ? ' → ${accountName(entry.toAccountId!)}' : ''}',
        style: const TextStyle(fontSize: 11, color: muted),
        maxLines: 2,
      ),
      trailing: Text(
        '${transfer
            ? ''
            : income
            ? '+'
            : '−'}${money(entry.cents)}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: income ? forest : ink,
        ),
      ),
      onTap: busy ? null : () => editEntry(entry),
    );
  }
}

Widget panel(Widget child) => Material(
  clipBehavior: Clip.antiAlias,
  color: Colors.white,
  borderRadius: BorderRadius.circular(24),
  child: child,
);

Widget sectionTitle(String title, {String? action, VoidCallback? onTap}) => Row(
  children: [
    Expanded(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    ),
    if (action != null) TextButton(onPressed: onTap, child: Text(action)),
  ],
);

Widget emptyState(String title, String subtitle) => panel(
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Column(
      children: [
        const Icon(Icons.eco_outlined, size: 38, color: forest),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, color: ink),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, height: 1.7, color: muted),
        ),
      ],
    ),
  ),
);

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.ledger,
    this.entry,
    required this.onSave,
    this.onDelete,
  });
  final Ledger ledger;
  final LedgerEntry? entry;
  final Future<bool> Function(LedgerEntry) onSave;
  final Future<bool> Function()? onDelete;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late EntryType type;
  late String category;
  late String account;
  late String destination;
  late DateTime date;
  final form = GlobalKey<FormState>();
  late TextEditingController amount;
  late TextEditingController note;
  bool saving = false;
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    type = entry?.type ?? EntryType.expense;
    category = entry?.category ?? widget.ledger.expenseCategories.first;
    account = entry?.accountId ?? widget.ledger.accounts.first.id;
    destination =
        entry?.toAccountId ??
        widget.ledger.accounts
            .firstWhere(
              (a) => a.id != account,
              orElse: () => widget.ledger.accounts.first,
            )
            .id;
    date = entry?.date ?? DateTime.now();
    amount = TextEditingController(
      text: entry == null ? '' : money(entry.cents),
    );
    note = TextEditingController(text: entry?.note ?? '');
    amount.addListener(markDirty);
    note.addListener(markDirty);
  }

  void markDirty() {
    if (!dirty) setState(() => dirty = true);
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    final entry = LedgerEntry(
      id: widget.entry?.id ?? 'e${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      cents: parseMoney(amount.text),
      date: date,
      category: type == EntryType.transfer ? '转账' : category,
      accountId: account,
      toAccountId: type == EntryType.transfer ? destination : null,
      note: note.text.trim(),
    );
    final result = await widget.onSave(entry);
    if (!mounted) return;
    setState(() {
      saving = false;
      if (result) dirty = false;
    });
    if (result) Navigator.pop(context);
  }

  Future<void> requestClose() async {
    if (saving) return;
    if (!dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃这次修改？'),
        content: const Text('这笔账单还没有保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续记账'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = type == EntryType.income
        ? widget.ledger.incomeCategories
        : widget.ledger.expenseCategories;
    return PopScope(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry == null ? '记下这一笔' : '编辑账单'),
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: requestClose,
          ),
          actions: [
            if (widget.onDelete != null)
              IconButton(
                tooltip: '删除账单',
                icon: const Icon(Icons.delete_outline),
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        final deleted = await widget.onDelete!();
                        if (!mounted) return;
                        setState(() {
                          saving = false;
                          if (deleted) dirty = false;
                        });
                        if (deleted) Navigator.pop(this.context);
                      },
              ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SegmentedButton<EntryType>(
                  segments: [
                    const ButtonSegment(
                      value: EntryType.expense,
                      label: Text('支出'),
                    ),
                    const ButtonSegment(
                      value: EntryType.income,
                      label: Text('收入'),
                    ),
                    ButtonSegment(
                      value: EntryType.transfer,
                      label: const Text('转账'),
                      enabled: widget.ledger.accounts.length > 1,
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: saving
                      ? null
                      : (selected) => setState(() {
                          type = selected.single;
                          category =
                              (type == EntryType.income
                                      ? widget.ledger.incomeCategories
                                      : widget.ledger.expenseCategories)
                                  .first;
                          dirty = true;
                        }),
                ),
                const SizedBox(height: 30),
                const Text(
                  '金额 · 人民币',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: amount,
                  enabled: !saving,
                  autofocus: widget.entry == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                    color: forest,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '¥ ',
                    hintText: '0.00',
                    filled: false,
                  ),
                  validator: (text) {
                    try {
                      if (parseMoney(text ?? '') <= 0) return '金额需要大于零';
                    } on FormatException catch (error) {
                      return error.message;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (type != EntryType.transfer) ...[
                  const Text(
                    '选个分类',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 9,
                    runSpacing: 8,
                    children: categories
                        .map(
                          (name) => ChoiceChip(
                            avatar: Icon(categoryIcon(name), size: 18),
                            label: Text(name),
                            selected: category == name,
                            onSelected: saving
                                ? null
                                : (_) => setState(() {
                                    category = name;
                                    dirty = true;
                                  }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                ],
                DropdownButtonFormField<String>(
                  initialValue: account,
                  decoration: InputDecoration(
                    labelText: type == EntryType.transfer ? '转出账户' : '记入账户',
                  ),
                  items: widget.ledger.accounts
                      .map(
                        (a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() {
                          account = value!;
                          if (destination == account) {
                            destination = widget.ledger.accounts
                                .firstWhere(
                                  (a) => a.id != account,
                                  orElse: () => widget.ledger.accounts.first,
                                )
                                .id;
                          }
                          dirty = true;
                        }),
                ),
                if (type == EntryType.transfer) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('$account/$destination'),
                    initialValue: destination,
                    decoration: const InputDecoration(labelText: '转入账户'),
                    items: widget.ledger.accounts
                        .where((a) => a.id != account)
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setState(() {
                            destination = value!;
                            dirty = true;
                          }),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '转账仅改变账户余额，不计入收支。',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
                const SizedBox(height: 16),
                panel(
                  ListTile(
                    leading: const Icon(
                      Icons.calendar_today_outlined,
                      size: 20,
                    ),
                    title: Text('${date.year} 年 ${date.month} 月 ${date.day} 日'),
                    trailing: const Icon(Icons.expand_more),
                    onTap: saving
                        ? null
                        : () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (selected != null && mounted) {
                              setState(() {
                                date = selected;
                                dirty = true;
                              });
                            }
                          },
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: note,
                  enabled: !saving,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '给这一笔留点生活的细节',
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(saving ? '正在保存…' : '保存这一笔'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

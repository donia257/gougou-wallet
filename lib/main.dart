import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'backup_page.dart';
import 'category_page.dart';
import 'entry_editor.dart';
import 'ledger.dart';
import 'repository.dart';
import 'ui.dart';
import 'update_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: walletOverlay,
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
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide.none,
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFFDDE7D7),
        labelStyle: const TextStyle(
          color: ink,
          fontFamily: 'DailySans',
          fontFamilyFallback: ['DailyChinese'],
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: forest,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
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

class LedgerHome extends StatefulWidget {
  const LedgerHome({super.key, this.repository});
  final LedgerRepository? repository;
  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  late final repository = widget.repository ?? LedgerRepository();
  Ledger? ledger;
  bool loading = true;
  bool busy = false;
  bool loadFailed = false;
  int page = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTimeRange? range;
  EntryType? filter;
  String? filterAccount;
  String? filterCategory;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      final result = await repository.open();
      if (mounted) {
        setState(() {
          ledger = result;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loadFailed = true;
          loading = false;
        });
      }
    }
  }

  Future<bool> commit(Ledger next, {String? snapshotReason}) async {
    if (busy) return false;
    setState(() => busy = true);
    try {
      await repository.save(next, snapshotReason: snapshotReason);
      if (mounted) {
        setState(() {
          ledger = next;
          loadFailed = false;
          if (!next.categories.any((c) => c.id == filterCategory)) {
            filterCategory = null;
          }
          if (!next.accounts.any((a) => a.id == filterAccount)) {
            filterAccount = null;
          }
        });
      }
      return true;
    } catch (_) {
      if (mounted) showMessage(context, '保存失败，请检查存储空间后重试');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editEntry([LedgerEntry? entry, bool copy = false]) async {
    if (busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EntryEditor(
          ledger: ledger!,
          entry: entry,
          copy: copy,
          onSave: (value) => commit(
            ledger!.copyWith(
              lastAccountId: value.accountId,
              entries: [
                ...ledger!.entries.where((e) => e.id != value.id),
                value,
              ],
            ),
          ),
          onCopy: entry == null ? null : () => editEntry(entry, true),
          onDelete: entry == null
              ? null
              : () async {
                  if (!await confirmAction(
                    this.context,
                    '删除这笔账单？',
                    '删除后会重新计算收支、预算和关联余额。',
                  )) {
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

  Future<void> openBackup() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => BackupPage(
        repository: repository,
        currentLedger: () => ledger,
        onRestore: (next, reason) => commit(next, snapshotReason: reason),
      ),
    ),
  );

  Future<void> setBudget() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          BudgetDialog(month: month, cents: ledger!.budgets[monthKey(month)]),
    );
    if (result == null || !mounted) return;
    final budgets = Map<String, int>.from(ledger!.budgets);
    if (result.isEmpty) {
      budgets.remove(monthKey(month));
    } else {
      budgets[monthKey(month)] = parseMoney(result);
    }
    await commit(ledger!.copyWith(budgets: budgets));
  }

  List<LedgerEntry> get monthlyEntries => ledger!.selectEntries(
    start: month,
    end: DateTime(month.year, month.month + 1, 0),
  );
  List<LedgerEntry> get filteredEntries => ledger!.selectEntries(
    start: range?.start ?? month,
    end: range?.end ?? DateTime(month.year, month.month + 1, 0),
    type: filter,
    accountId: filterAccount,
    categoryId: filterCategory,
    query: search.text,
  );
  void clearFilters() => setState(() {
    range = null;
    filter = null;
    filterAccount = null;
    filterCategory = null;
    search.clear();
  });

  Future<void> pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange:
          range ??
          DateTimeRange(
            start: month,
            end: DateTime(month.year, month.month + 1, 0),
          ),
    );
    if (selected != null && mounted) setState(() => range = selected);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (loadFailed || ledger == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 48, color: forest),
                  const SizedBox(height: 18),
                  const Text(
                    '账本暂时无法打开',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '可重试读取，或选择本机快照、外部备份恢复账本。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: load, child: const Text('重新打开')),
                  TextButton(onPressed: openBackup, child: const Text('恢复账本')),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final monthly = monthlyEntries;
    final bills = page == 1 ? filteredEntries : <LedgerEntry>[];
    final rows = groupedRows(bills);
    return Scaffold(
      extendBody: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: walletOverlay,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: ValueKey(page),
                slivers: [
                  WalletSliverHeader(expanded: header()),
                  if (busy)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
                    sliver: SliverList.list(
                      children: switch (page) {
                        0 => homeContent(),
                        1 => billControls(bills),
                        2 => statsContent(monthly),
                        _ => settingsContent(),
                      },
                    ),
                  ),
                  if (page == 1)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      sliver: rows.isEmpty
                          ? SliverToBoxAdapter(
                              child: emptyState('这里还没有账单', '试试调整日期或筛选条件。'),
                            )
                          : SliverList.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, index) =>
                                  rows[index] is DaySummary
                                  ? dayHeader(rows[index] as DaySummary)
                                  : entryTile(
                                      rows[index] as LedgerEntry,
                                      last:
                                          index == rows.length - 1 ||
                                          rows[index + 1] is DaySummary,
                                    ),
                            ),
                    ),
                  SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final remaining =
                          constraints.viewportMainAxisExtent -
                          constraints.precedingScrollExtent +
                          WalletSliverHeader.expandedExtent(context) -
                          kToolbarHeight;
                      return SliverToBoxAdapter(
                        child: SizedBox(
                          height: remaining > 110 ? remaining : 110,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: page == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: busy ? null : () => editEntry(),
              backgroundColor: forest,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
            ),
      bottomNavigationBar: WalletGlassSurface(
        bottom: true,
        child: NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (value) => setState(() => page = value),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: const Color(0xFFDDE7D7),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.cottage_outlined),
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
              icon: Icon(Icons.settings_outlined),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }

  Widget header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/brand/wangwang-wallet-logo.png',
              width: 36,
              height: 36,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '汪汪钱包',
              style: TextStyle(color: forest, fontWeight: FontWeight.w700),
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
                    icon: const Icon(Icons.chevron_left),
                    onPressed: month.year == 1900 && month.month == 1
                        ? null
                        : () => setState(() {
                            month = DateTime(month.year, month.month - 1);
                            range = null;
                          }),
                  ),
                  Text(
                    '${month.year}\n${month.month} 月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: forest),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: month.year == 2100 && month.month == 12
                        ? null
                        : () => setState(() {
                            month = DateTime(month.year, month.month + 1);
                            range = null;
                          }),
                  ),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        ['把日子，慢慢记好。', '每一笔，都有迹可循。', '看见生活的去向。', '让记账更顺手。'][page],
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
            const Text(
              '这个月，花了多少',
              style: TextStyle(color: Color(0xFFD9E7CD), fontSize: 13),
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
      const SizedBox(height: 20),
      sectionTitle('本月足迹', action: '查看账单', onTap: () => openBills()),
      const SizedBox(height: 8),
      dailyOverview(),
    ];
  }

  void openBills({DateTime? day}) => setState(() {
    range = null;
    filter = null;
    filterAccount = null;
    filterCategory = null;
    search.clear();
    if (day != null) range = DateTimeRange(start: day, end: day);
    page = 1;
  });

  Widget dailyOverview() {
    final entries = monthlyEntries;
    final days = entries.map((e) => dayKey(e.date)).toSet().length;
    final now = DateTime.now();
    final currentMonth = monthKey(month) == monthKey(now);
    final today = entries.where((e) => dayKey(e.date) == dayKey(now)).toList();
    final todayExpense = today
        .where((e) => e.type == EntryType.expense)
        .fold(0, (sum, e) => sum + e.cents);
    return panel(
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.spa_outlined, color: forest, size: 28),
            const SizedBox(height: 14),
            Text(
              entries.isEmpty ? '从今天的第一笔开始' : '已记下 $days 天的生活',
              style: const TextStyle(
                color: ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entries.isEmpty
                  ? '一顿早餐，一次出行，都值得被认真记录。'
                  : '这个月共记录 ${entries.length} 笔，慢慢积累自己的生活足迹。',
              style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
            ),
            if (currentMonth) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1, color: paper),
              ),
              Text(
                '今日支出  ¥ ${money(todayExpense)}',
                style: const TextStyle(
                  color: forest,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                today.isEmpty
                    ? '今天还没有记录，随时记下一笔。'
                    : '今天记录了 ${today.length} 笔收支与转账。',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => openBills(day: dayStart(now)),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('查看今日账单'),
              ),
            ],
          ],
        ),
      ),
    );
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
        onTap: busy ? null : setBudget,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.track_changes_rounded, color: forest, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '生活预算',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: muted),
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

  List<Widget> billControls(List<LedgerEntry> bills) {
    final income = bills
        .where((e) => e.type == EntryType.income)
        .fold(0, (sum, e) => sum + e.cents);
    final expense = bills
        .where((e) => e.type == EntryType.expense)
        .fold(0, (sum, e) => sum + e.cents);
    return [
      TextField(
        controller: search,
        decoration: const InputDecoration(
          hintText: '搜索备注、分类或账户',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final pair in <(String, EntryType?)>[
            ('全部', null),
            ('支出', EntryType.expense),
            ('收入', EntryType.income),
            ('转账', EntryType.transfer),
          ])
            ChoiceChip(
              label: Text(pair.$1),
              selected: filter == pair.$2,
              onSelected: (_) => setState(() {
                filter = pair.$2;
                if (filterCategory != null &&
                    filter != null &&
                    ledger!.categoryById(filterCategory!).type != filter) {
                  filterCategory = null;
                }
              }),
            ),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
              range == null
                  ? '自定义日期'
                  : '${dayKey(range!.start)} 至 ${dayKey(range!.end)}',
            ),
            onPressed: pickRange,
          ),
          PopupMenuButton<String>(
            tooltip: '按账户筛选',
            initialValue: filterAccount ?? '',
            itemBuilder: (context) => [
              const PopupMenuItem(value: '', child: Text('全部账户')),
              ...ledger!.accounts.map(
                (a) => PopupMenuItem(value: a.id, child: Text(a.name)),
              ),
            ],
            onSelected: (value) =>
                setState(() => filterAccount = value.isEmpty ? null : value),
            child: Chip(
              avatar: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(
                filterAccount == null
                    ? '全部账户'
                    : ledger!.accountName(filterAccount!),
              ),
            ),
          ),
          if (filter != EntryType.transfer)
            PopupMenuButton<String>(
              tooltip: '按分类筛选',
              initialValue: filterCategory ?? '',
              itemBuilder: (context) => [
                const PopupMenuItem(value: '', child: Text('全部分类')),
                ...ledger!.categories
                    .where((c) => filter == null || c.type == filter)
                    .map(
                      (c) => PopupMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.type == EntryType.expense ? '支出' : '收入'} · ${c.name}',
                        ),
                      ),
                    ),
              ],
              onSelected: (value) =>
                  setState(() => filterCategory = value.isEmpty ? null : value),
              child: Chip(
                avatar: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(
                  filterCategory == null
                      ? '全部分类'
                      : ledger!.categoryById(filterCategory!).name,
                ),
              ),
            ),
          TextButton(onPressed: clearFilters, child: const Text('清除筛选')),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '共 ${bills.length} 笔',
        style: const TextStyle(color: ink, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        '支出 ¥ ${money(expense)}  ·  收入 ¥ ${money(income)}\n结余 ¥ ${money(income - expense)}',
        style: const TextStyle(color: muted, fontSize: 12, height: 1.8),
      ),
      const SizedBox(height: 14),
    ];
  }

  List<Widget> statsContent(List<LedgerEntry> monthly) {
    final expenses = monthly.where((e) => e.type == EntryType.expense);
    final total = expenses.fold(0, (sum, e) => sum + e.cents);
    final totals = <String, int>{};
    final daily = <int, int>{};
    for (final entry in expenses) {
      totals.update(
        entry.category,
        (value) => value + entry.cents,
        ifAbsent: () => entry.cents,
      );
      daily.update(
        entry.date.day,
        (value) => value + entry.cents,
        ifAbsent: () => entry.cents,
      );
    }
    final ranking = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxDay = daily.values.fold(
      1,
      (value, next) => next > value ? next : value,
    );
    return [
      panel(
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本月支出', style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '¥ ${money(total)}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      sectionTitle('每日支出趋势'),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '左右滑动，点击日期查看当天支出',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
      panel(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (
                  var day = 1;
                  day <= DateTime(month.year, month.month + 1, 0).day;
                  day++
                )
                  Semantics(
                    label:
                        '${month.month} 月 $day 日，支出 ${money(daily[day] ?? 0)} 元',
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() {
                        final date = DateTime(month.year, month.month, day);
                        range = DateTimeRange(start: date, end: date);
                        filter = EntryType.expense;
                        filterAccount = null;
                        filterCategory = null;
                        search.clear();
                        page = 1;
                      }),
                      child: SizedBox(
                        width: 34,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 88,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: 16,
                                  height: 3 + 80 * (daily[day] ?? 0) / maxDay,
                                  decoration: BoxDecoration(
                                    color: daily.containsKey(day)
                                        ? forest
                                        : const Color(0xFFE3E9DE),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$day',
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
            padding: const EdgeInsets.all(18),
            child: Column(
              children: ranking.map((item) {
                final category = ledger!.categoryById(item.key);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            categoryIcon(category.icon),
                            size: 20,
                            color: forest,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(category.name)),
                          Text(
                            '¥ ${money(item.value)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: item.value / total,
                        color: forest,
                        backgroundColor: paper,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${(item.value * 100 / total).toStringAsFixed(1)}%',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      const SizedBox(height: 20),
      budgetCard(),
    ];
  }

  List<Widget> settingsContent() => [
    sectionTitle('记账偏好'),
    const SizedBox(height: 12),
    panel(
      Column(
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined, color: forest),
            title: const Text('分类管理'),
            subtitle: const Text('添加、编辑、删除与排序'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          CategoryPage(ledger: ledger!, onSave: commit),
                    ),
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.track_changes, color: forest),
            title: const Text('生活预算'),
            subtitle: Text('${month.year} 年 ${month.month} 月'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : setBudget,
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    sectionTitle('数据与应用'),
    const SizedBox(height: 12),
    panel(
      Column(
        children: [
          ListTile(
            leading: const Icon(Icons.backup_outlined, color: forest),
            title: const Text('数据与备份'),
            subtitle: const Text('导出、恢复与本机快照'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : openBackup,
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded, color: forest),
            title: const Text('检查更新'),
            subtitle: const Text('GitHub 正式版本'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (context) => const UpdatePage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: forest),
            title: const Text('关于汪汪钱包'),
            subtitle: const Text('v$appVersion · 构建 $appBuild'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '汪汪钱包',
              applicationVersion: 'v$appVersion',
              applicationIcon: Image.asset(
                'assets/brand/wangwang-wallet-logo.png',
                width: 48,
                height: 48,
              ),
              children: const [Text('认真记下每一天的生活。账本保存在本机，支持 JSON 完整备份。')],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    const Text(
      '账本保存在这台手机上，请定期导出重要数据。',
      style: TextStyle(color: muted, fontSize: 12, height: 1.7),
    ),
  ];

  Widget dayHeader(DaySummary summary) {
    final now = DateTime.now();
    final date = summary.date;
    final title = dayKey(date) == dayKey(now)
        ? '今天'
        : dayKey(date) == dayKey(now.subtract(const Duration(days: 1)))
        ? '昨天'
        : '${date.year == now.year ? '' : '${date.year} 年 '}${dayLabel(date)}';
    return Padding(
      key: ValueKey('day-${dayKey(date)}'),
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '支出 ${money(summary.expense)} · 收入 ${money(summary.income)}',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: paper),
            ],
          ),
        ),
      ),
    );
  }

  Widget entryTile(LedgerEntry entry, {bool last = false}) {
    final label = ledger!.categoryName(entry);
    final icon = entry.type == EntryType.transfer
        ? '转账'
        : ledger!.categoryById(entry.category).icon;
    final income = entry.type == EntryType.income;
    final transfer = entry.type == EntryType.transfer;
    return Material(
      key: ValueKey('entry-${entry.id}'),
      color: Colors.white,
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(last ? cardRadius : 0),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF4EDE1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(categoryIcon(icon), size: 22, color: forest),
        ),
        title: Text(
          entry.note.isEmpty ? label : entry.note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${timeLabel(entry.date)} · $label · ${ledger!.accountName(entry.accountId)}'
          '${transfer ? ' → ${ledger!.accountName(entry.toAccountId!)}' : ''}',
          maxLines: 2,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        trailing: Text(
          '${transfer
              ? ''
              : income
              ? '+'
              : '−'}${money(entry.cents)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: income ? forest : ink,
          ),
        ),
        onTap: busy ? null : () => editEntry(entry),
      ),
    );
  }
}

class DaySummary {
  DaySummary(this.date);
  final DateTime date;
  int expense = 0;
  int income = 0;
}

List<Object> groupedRows(List<LedgerEntry> entries) {
  final result = <Object>[];
  DaySummary? current;
  for (final entry in entries) {
    if (current == null || dayKey(current.date) != dayKey(entry.date)) {
      current = DaySummary(dayStart(entry.date));
      result.add(current);
    }
    if (entry.type == EntryType.expense) current.expense += entry.cents;
    if (entry.type == EntryType.income) current.income += entry.cents;
    result.add(entry);
  }
  return result;
}

class BudgetDialog extends StatefulWidget {
  const BudgetDialog({super.key, required this.month, this.cents});
  final DateTime month;
  final int? cents;
  @override
  State<BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<BudgetDialog> {
  final form = GlobalKey<FormState>();
  late final controller = TextEditingController(
    text: widget.cents == null ? '' : money(widget.cents!),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.month.month} 月生活预算'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '输入金额，留空移除预算'),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return null;
          try {
            if (parseMoney(value) <= 0) return '预算应大于零';
          } on FormatException catch (error) {
            return error.message;
          }
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('保存预算'),
      ),
    ],
  );
}

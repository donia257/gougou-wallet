import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'bill_import.dart';
import 'import_files.dart';
import 'category_rules.dart';
import 'ledger.dart';
import 'selection_ui.dart';
import 'ui.dart';

ImportPreview _parseRequest((List<int>, String, Ledger) request) =>
    parseBillFile(request.$1, request.$2, request.$3);

class BillImportPage extends StatefulWidget {
  const BillImportPage({
    super.key,
    required this.currentLedger,
    required this.onCommit,
  });
  final Ledger Function() currentLedger;
  final Future<bool> Function(Ledger, String) onCommit;
  @override
  State<BillImportPage> createState() => _BillImportPageState();
}

class _BillImportPageState extends State<BillImportPage> {
  bool busy = false;

  Future<void> pickFile() async {
    if (busy) return;
    setState(() => busy = true);
    ImportPreview? preview;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null) return;
      final file = result.files.single;
      final bytes = await readImportFile(file);
      preview = await compute(_parseRequest, (
        bytes,
        file.name,
        widget.currentLedger(),
      ));
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message.toString());
    } catch (_) {
      if (mounted) showMessage(context, '无法解析文件，请选择已解压的微信或支付宝 CSV / XLSX 原始账单');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted || preview == null) return;
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BillImportPreviewPage(
          preview: preview!,
          currentLedger: widget.currentLedger,
          onCommit: widget.onCommit,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
      if (imported == true) showMessage(context, '导入完成，可在导入记录中撤销');
    }
  }

  Future<void> undo(ImportBatch batch) async {
    if (busy) return;
    final ledger = widget.currentLedger();
    final entries = ledger.entries
        .where((e) => e.importBatchId == batch.id)
        .toList();
    final edited = entries
        .where((e) => entryFingerprint(e) != batch.fingerprints[e.id])
        .length;
    final confirmed = await confirmAction(
      context,
      '撤销这次导入？',
      '将删除该批次现存的 ${entries.length} 笔账单，其中 $edited 笔导入后已修改，修改也会一并删除。'
          '其他批次、手动新增或复制的账单会保留。账户余额、统计及预算将重新计算。',
    );
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    try {
      final next = undoBillImport(widget.currentLedger(), batch.id);
      final success = await widget.onCommit(next, '撤销导入之前');
      if (mounted && success) showMessage(context, '本次导入已撤销，可重新导入');
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.currentLedger();
    final batches = ledger.importBatches.reversed.toList();
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('账单导入')),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            sectionTitle('把流水带进钱包'),
            const SizedBox(height: 12),
            const Text(
              '微信与支付宝 · 本机解析',
              style: TextStyle(color: forest, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '支持 CSV（UTF-8 / GBK）及 XLSX，每份不超过 20 MB、5 万行。'
              '请先解压下载的账单，再选择原始文件。导入会追加记录，不替换现有账本。',
              style: TextStyle(color: muted, height: 1.7),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: busy ? null : pickFile,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(busy ? '正在处理…' : '选择微信 / 支付宝账单'),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 14),
            const Text(
              '微信：账单 → 常见问题 → 下载账单，选择用于个人对账。\n'
              '支付宝：账单 → 更多 → 开具交易流水证明 / 导出账单，选择用于个人对账。\n'
              '入口名称可能随支付应用版本变化。退款、关闭交易及不计收支记录会单独列出，请在预览中核对。',
              style: TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
            const SizedBox(height: 28),
            sectionTitle('导入记录'),
            const SizedBox(height: 12),
            if (batches.isEmpty) emptyState('还没有导入记录', '先预览、再确认，每次导入都可单独撤销。'),
            for (final batch in batches)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: panel(
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${batch.platform} · ${batch.fingerprints.length} 笔',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          batch.fileName,
                          style: const TextStyle(color: muted),
                        ),
                        Text(
                          '${dayKey(batch.createdAt)} ${timeLabel(batch.createdAt)}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: busy ? null : () => undo(batch),
                            icon: const Icon(Icons.undo_rounded),
                            label: const Text('撤销本次导入'),
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
    );
  }
}

class BillImportPreviewPage extends StatefulWidget {
  const BillImportPreviewPage({
    super.key,
    required this.preview,
    required this.currentLedger,
    required this.onCommit,
  });
  final ImportPreview preview;
  final Ledger Function() currentLedger;
  final Future<bool> Function(Ledger, String) onCommit;
  @override
  State<BillImportPreviewPage> createState() => _BillImportPreviewPageState();
}

class _BillImportPreviewPageState extends State<BillImportPreviewPage> {
  final selected = <int>{};
  final categories = <int, String>{};
  late String account;
  bool busy = false;
  ImportDisposition? filter;
  Ledger get ledger => widget.currentLedger();

  @override
  void initState() {
    super.initState();
    final preferred = widget.preview.platform == '微信' ? 'wechat' : 'alipay';
    account = ledger.accounts.any((a) => a.id == preferred)
        ? preferred
        : ledger.lastAccountId;
    for (final row in widget.preview.rows) {
      if (row.disposition == ImportDisposition.ready) selected.add(row.line);
      if (row.selectable) {
        categories[row.line] = fallbackCategory(ledger, row.type!);
      }
    }
  }

  Future<void> chooseCategory(EntryType type, {ImportRow? row}) async {
    final result = await showWalletChoices<String>(
      context,
      title: row == null
          ? '批量设置${type == EntryType.income ? '收入' : '支出'}分类'
          : '选择这笔账单的分类',
      selected: row == null
          ? ledger.categoriesFor(type).first.id
          : categories[row.line]!,
      options: ledger
          .categoriesFor(type)
          .map((c) => WalletOption(c.id, c.name, icon: categoryIcon(c.icon)))
          .toList(),
    );
    if (result == null || !mounted) return;
    setState(() {
      for (final item in widget.preview.rows) {
        if (item.selectable &&
            item.type == type &&
            (row == null || row.line == item.line)) {
          categories[item.line] = result;
        }
      }
    });
  }

  Future<void> save() async {
    if (busy || selected.isEmpty) return;
    if (!await confirmAction(
      context,
      '确认导入 ${selected.length} 笔？',
      '所选交易将追加到「${ledger.accountName(account)}」。未勾选、重复及排除项不会写入。导入前会保留本机恢复快照。',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final next = applyBillImport(
        ledger,
        widget.preview,
        selected,
        account,
        categories,
      );
      final success = await widget.onCommit(
        next,
        '导入${widget.preview.platform}账单之前',
      );
      if (!mounted) return;
      setState(() => busy = false);
      if (success) Navigator.pop(context, true);
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message.toString());
    } finally {
      if (mounted && busy) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.preview.rows;
    final visible = filter == null
        ? rows
        : rows.where((r) => r.disposition == filter).toList();
    final counts = {
      for (final d in ImportDisposition.values)
        d: rows.where((r) => r.disposition == d).length,
    };
    var income = 0;
    var expense = 0;
    for (final row in rows.where((r) => selected.contains(r.line))) {
      if (row.type == EntryType.income) {
        income += row.cents!;
      } else {
        expense += row.cents!;
      }
    }
    const labels = {
      ImportDisposition.ready: '可导入',
      ImportDisposition.review: '待核对',
      ImportDisposition.duplicate: '重复',
      ImportDisposition.excluded: '已排除',
      ImportDisposition.invalid: '异常',
    };
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.preview.platform}账单预览')),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(22),
              sliver: SliverList.list(
                children: [
                  Text(
                    widget.preview.fileName,
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  sectionTitle('先核对，再入账'),
                  const SizedBox(height: 8),
                  Text(
                    '共 ${rows.length} 条明细 · 已选 ${selected.length} 笔\n'
                    '收入 ¥ ${money(income)} · 支出 ¥ ${money(expense)}',
                    style: const TextStyle(
                      color: forest,
                      height: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  WalletSelectField(
                    label: '全部所选交易记入账户',
                    value: ledger.accountName(account),
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: busy
                        ? null
                        : () async {
                            final value = await showWalletChoices<String>(
                              context,
                              title: '选择入账账户',
                              selected: account,
                              options: ledger.accounts
                                  .map((a) => WalletOption(a.id, a.name))
                                  .toList(),
                            );
                            if (mounted && value != null) {
                              setState(() => account = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '支付平台不一定是实际扣款账户；如包含多张银行卡，可分次勾选后导入。分类默认使用“其他”，可逐笔或批量调整。'
                    '待核对项默认不选，退款相关记录不自动入账。',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => chooseCategory(EntryType.expense),
                        child: const Text('批量支出分类'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => chooseCategory(EntryType.income),
                        child: const Text('批量收入分类'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                if (selected.isNotEmpty) {
                                  selected.clear();
                                } else {
                                  selected.addAll(
                                    rows
                                        .where(
                                          (r) =>
                                              r.disposition ==
                                              ImportDisposition.ready,
                                        )
                                        .map((r) => r.line),
                                  );
                                }
                              }),
                        child: Text(selected.isEmpty ? '选择可导入项' : '取消全选'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: Text('全部 ${rows.length}'),
                        selected: filter == null,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => filter = null),
                      ),
                      for (final d in ImportDisposition.values)
                        ChoiceChip(
                          label: Text('${labels[d]} ${counts[d]}'),
                          selected: filter == d,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => filter = d),
                        ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final row = visible[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: panel(
                      Column(
                        children: [
                          CheckboxListTile(
                            value: selected.contains(row.line),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: busy || !row.selectable
                                ? null
                                : (value) => setState(() {
                                    if (value == true) {
                                      selected.add(row.line);
                                    } else {
                                      selected.remove(row.line);
                                    }
                                  }),
                            title: Text(
                              row.description.isEmpty
                                  ? '第 ${row.line} 行'
                                  : row.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '第 ${row.line} 行 · ${labels[row.disposition]}\n'
                              '${row.date == null ? '' : '${dayKey(row.date!)} ${timeLabel(row.date!)} · '}'
                              '${row.cents == null ? '' : '${row.type == EntryType.income ? '收入' : '支出'} ¥ ${money(row.cents!)}\n'}'
                              '${row.reason}',
                            ),
                          ),
                          if (row.selectable)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => chooseCategory(row.type!, row: row),
                                child: Text(
                                  '分类：${ledger.categoryById(categories[row.line]!).name}',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
            child: FilledButton(
              onPressed: busy || selected.isEmpty ? null : save,
              child: Text(busy ? '正在导入…' : '确认导入 ${selected.length} 笔'),
            ),
          ),
        ),
      ),
    );
  }
}

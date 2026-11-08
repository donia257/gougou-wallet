import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ledger.dart';
import 'ui.dart';
import 'selection_ui.dart';
import 'ocr_service.dart';
import 'receipt_parser.dart';
import 'receipt_review_page.dart';

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.ledger,
    required this.onSave,
    this.entry,
    this.copy = false,
    this.onDelete,
    this.onCopy,
    this.ocrService,
  });
  final Ledger ledger;
  final LedgerEntry? entry;
  final bool copy;
  final Future<bool> Function(LedgerEntry) onSave;
  final Future<bool> Function()? onDelete;
  final VoidCallback? onCopy;
  final OcrService? ocrService;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  final amountFocus = FocusNode(debugLabel: 'entry-amount');
  late final amount = TextEditingController(
    text: widget.entry == null ? '' : money(widget.entry!.cents),
  );
  late final note = TextEditingController(text: widget.entry?.note ?? '');
  late EntryType type = widget.entry?.type ?? EntryType.expense;
  late String category =
      widget.entry?.category ?? widget.ledger.categoriesFor(type).first.id;
  late String account = widget.entry?.accountId ?? widget.ledger.lastAccountId;
  late String destination =
      widget.entry?.toAccountId ??
      widget.ledger.accounts
          .firstWhere(
            (a) => a.id != account,
            orElse: () => widget.ledger.accounts.first,
          )
          .id;
  late DateTime date = widget.copy
      ? DateTime.now()
      : widget.entry?.date ?? DateTime.now();
  bool saving = false;
  bool saved = false;
  bool scanning = false;
  bool recognized = false;
  bool get locked => saving || scanning;
  bool get editing => widget.entry != null && !widget.copy;

  @override
  void initState() {
    super.initState();
    // Request the initial keyboard once, rather than autofocus when a lazily
    // built input is recreated after a selector scrolls it out of view.
    if (widget.entry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) amountFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    amountFocus.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save({bool continueAdding = false}) async {
    if (locked || !form.currentState!.validate()) return;
    setState(() => saving = true);
    final entry = LedgerEntry(
      id: editing
          ? widget.entry!.id
          : 'e${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      cents: parseMoney(amount.text),
      date: date,
      category: type == EntryType.transfer ? 'transfer' : category,
      accountId: account,
      toAccountId: type == EntryType.transfer ? destination : null,
      note: note.text.trim(),
      importBatchId: editing ? widget.entry!.importBatchId : null,
      sourceKey: editing ? widget.entry!.sourceKey : null,
    );
    var success = false;
    try {
      success = await widget.onSave(entry);
    } catch (_) {
      if (mounted) showMessage(context, '保存失败，请重试');
    }
    if (!mounted) return;
    setState(() => saving = false);
    if (!success) return;
    if (continueAdding) {
      form.currentState!.reset();
      amount.clear();
      note.clear();
      setState(() {
        date = DateTime.now();
        saved = true;
        recognized = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> pickDate() async {
    final range = await showWalletDateSheet(
      context,
      initial: DateTimeRange(start: dayStart(date), end: dayStart(date)),
      range: false,
    );
    final selected = range?.start;
    if (selected != null && mounted) {
      setState(
        () => date = DateTime(
          selected.year,
          selected.month,
          selected.day,
          date.hour,
          date.minute,
        ),
      );
    }
  }

  Future<void> scanReceipt() async {
    if (locked) return;
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    setState(() => scanning = true);
    try {
      final document = await (widget.ocrService ?? OcrService())
          .pickAndRecognize();
      if (!mounted || document == null) return;
      final suggestion = parseReceipt(document, widget.ledger);
      final draft = await Navigator.of(context).push<ReceiptDraft>(
        MaterialPageRoute(
          builder: (_) => ReceiptReviewPage(
            document: document,
            ledger: widget.ledger,
            suggestion: suggestion,
            currentDate: date,
            currentNote: note.text,
          ),
        ),
      );
      if (draft == null || !mounted) return;
      setState(() {
        amount.text = money(draft.cents);
        type = draft.type;
        category = draft.categoryId;
        note.text = draft.note;
        date = draft.date ?? date;
        saved = false;
        recognized = true;
      });
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message.toString());
    } on PlatformException catch (error) {
      if (mounted) showMessage(context, error.message ?? '图片识别失败，请重试');
    } catch (_) {
      if (mounted) showMessage(context, '无法识别这张图片，请选择清晰的支付截图或小票');
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> pickTime() async {
    final selected = await showWalletTimeSheet(
      context,
      TimeOfDay.fromDateTime(date),
    );
    if (selected != null && mounted) {
      setState(
        () => date = DateTime(
          date.year,
          date.month,
          date.day,
          selected.hour,
          selected.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          editing
              ? '编辑账单'
              : widget.copy
              ? '复制记一笔'
              : '记下这一笔',
        ),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: saving ? null : () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: '图片识别',
            onPressed: locked ? null : scanReceipt,
            icon: const Icon(Icons.image_search_rounded),
          ),
          if (editing) ...[
            TextButton(
              onPressed: locked ? null : widget.onCopy,
              child: const Text('复制'),
            ),
            IconButton(
              tooltip: '删除账单',
              icon: const Icon(Icons.delete_outline),
              onPressed: locked
                  ? null
                  : () async {
                      setState(() => saving = true);
                      final deleted = await widget.onDelete!();
                      if (!mounted) return;
                      setState(() => saving = false);
                      if (deleted && context.mounted) Navigator.pop(context);
                    },
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Form(
          key: form,
          child: Column(
            children: [
              if (scanning)
                const LinearProgressIndicator(semanticsLabel: '正在本机识别图片'),
              if (recognized)
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 8, 22, 0),
                  child: Text(
                    '识别结果已填入，请核对后保存',
                    style: TextStyle(color: forest),
                  ),
                ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(22),
                  children: [
                    WalletSegments<EntryType>(
                      options: [
                        const WalletOption(EntryType.expense, '支出'),
                        const WalletOption(EntryType.income, '收入'),
                        WalletOption(
                          EntryType.transfer,
                          '转账',
                          enabled: widget.ledger.accounts.length > 1,
                        ),
                      ],
                      selected: type,
                      onChanged: locked
                          ? null
                          : (value) => setState(() {
                              type = value;
                              category = type == EntryType.transfer
                                  ? 'transfer'
                                  : widget.ledger.categoriesFor(type).first.id;
                            }),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      '金额 · 人民币',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    TextFormField(
                      key: const ValueKey('entry-amount'),
                      controller: amount,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      onChanged: (_) {
                        if (saved) setState(() => saved = false);
                      },
                      enabled: !locked,
                      focusNode: amountFocus,
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
                    if (type != EntryType.transfer) ...[
                      const SizedBox(height: 22),
                      const Text(
                        '选个分类',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.ledger
                            .categoriesFor(type)
                            .map(
                              (c) => WalletPill(
                                icon: categoryIcon(c.icon),
                                label: c.name,
                                selected: category == c.id,
                                onTap: locked
                                    ? null
                                    : () => setState(() => category = c.id),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    WalletSelectField(
                      label: type == EntryType.transfer ? '转出账户' : '记入账户',
                      value: widget.ledger.accountName(account),
                      icon: Icons.account_balance_wallet_outlined,
                      onTap: locked
                          ? null
                          : () async {
                              final value = await showWalletChoices<String>(
                                context,
                                title: '选择账户',
                                selected: account,
                                options: widget.ledger.accounts
                                    .map(
                                      (a) => WalletOption(
                                        a.id,
                                        a.name,
                                        icon: Icons
                                            .account_balance_wallet_outlined,
                                      ),
                                    )
                                    .toList(),
                              );
                              if (value == null || !mounted) return;
                              setState(() {
                                account = value;
                                if (destination == account) {
                                  destination = widget.ledger.accounts
                                      .firstWhere(
                                        (a) => a.id != account,
                                        orElse: () =>
                                            widget.ledger.accounts.first,
                                      )
                                      .id;
                                }
                              });
                            },
                    ),
                    if (type == EntryType.transfer) ...[
                      const SizedBox(height: 12),
                      WalletSelectField(
                        label: '转入账户',
                        value: widget.ledger.accountName(destination),
                        icon: Icons.south_west_rounded,
                        onTap: locked
                            ? null
                            : () async {
                                final value = await showWalletChoices<String>(
                                  context,
                                  title: '选择转入账户',
                                  selected: destination,
                                  options: widget.ledger.accounts
                                      .where((a) => a.id != account)
                                      .map(
                                        (a) => WalletOption(
                                          a.id,
                                          a.name,
                                          icon: Icons
                                              .account_balance_wallet_outlined,
                                        ),
                                      )
                                      .toList(),
                                );
                                if (value != null && mounted) {
                                  setState(() => destination = value);
                                }
                              },
                      ),
                    ],
                    const SizedBox(height: 16),
                    panel(
                      Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.calendar_today_outlined,
                              color: forest,
                            ),
                            title: const Text('日期'),
                            trailing: Text('${date.year} 年 ${dayLabel(date)}'),
                            onTap: locked ? null : pickDate,
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(
                              Icons.schedule_rounded,
                              color: forest,
                            ),
                            title: const Text('时间'),
                            trailing: Text(timeLabel(date)),
                            onTap: locked ? null : pickTime,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('entry-note'),
                      controller: note,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      enabled: !locked,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        hintText: '给这一笔留点生活的细节',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              if (saved)
                const Text(
                  '已保存，可继续记账',
                  style: TextStyle(color: forest, fontSize: 12),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
                child: Row(
                  children: [
                    if (!editing) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: locked
                              ? null
                              : () => save(continueAdding: true),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('保存并继续'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: locked ? null : save,
                        child: Text(saving ? '正在保存…' : '保存这一笔'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

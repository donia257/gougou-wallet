import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ledger.dart';
import 'ui.dart';

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.ledger,
    required this.onSave,
    this.entry,
    this.copy = false,
    this.onDelete,
    this.onCopy,
  });
  final Ledger ledger;
  final LedgerEntry? entry;
  final bool copy;
  final Future<bool> Function(LedgerEntry) onSave;
  final Future<bool> Function()? onDelete;
  final VoidCallback? onCopy;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
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
  bool get editing => widget.entry != null && !widget.copy;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save({bool continueAdding = false}) async {
    if (saving || !form.currentState!.validate()) return;
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
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
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

  Future<void> pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
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
          if (editing) ...[
            TextButton(
              onPressed: saving ? null : widget.onCopy,
              child: const Text('复制'),
            ),
            IconButton(
              tooltip: '删除账单',
              icon: const Icon(Icons.delete_outline),
              onPressed: saving
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(22),
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
                          : (selection) => setState(() {
                              type = selection.single;
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
                      onChanged: (_) {
                        if (saved) setState(() => saved = false);
                      },
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
                              (c) => ChoiceChip(
                                avatar: Icon(categoryIcon(c.icon), size: 18),
                                label: Text(c.name),
                                selected: category == c.id,
                                onSelected: saving
                                    ? null
                                    : (_) => setState(() => category = c.id),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: account,
                      decoration: InputDecoration(
                        labelText: type == EntryType.transfer ? '转出账户' : '记入账户',
                      ),
                      items: widget.ledger.accounts
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
                              account = value!;
                              if (destination == account) {
                                destination = widget.ledger.accounts
                                    .firstWhere(
                                      (a) => a.id != account,
                                      orElse: () =>
                                          widget.ledger.accounts.first,
                                    )
                                    .id;
                              }
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
                            : (value) => setState(() => destination = value!),
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
                            onTap: saving ? null : pickDate,
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(
                              Icons.schedule_rounded,
                              color: forest,
                            ),
                            title: const Text('时间'),
                            trailing: Text(timeLabel(date)),
                            onTap: saving ? null : pickTime,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('entry-note'),
                      controller: note,
                      enabled: !saving,
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
                          onPressed: saving
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
                        onPressed: saving ? null : save,
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

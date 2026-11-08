import 'package:flutter/material.dart';
import 'ledger.dart';
import 'ui.dart';
import 'selection_ui.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.ledger, required this.onSave});
  final Ledger ledger;
  final Future<bool> Function(Ledger) onSave;
  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  late Ledger ledger = widget.ledger;
  EntryType type = EntryType.expense;
  bool saving = false;

  Future<void> persist(Ledger next) async {
    if (saving) return;
    setState(() => saving = true);
    final success = await widget.onSave(next);
    if (mounted) {
      setState(() {
        if (success) ledger = next;
        saving = false;
      });
    }
  }

  Future<void> edit([LedgerCategory? existing]) async {
    final category = await showDialog<LedgerCategory>(
      context: context,
      builder: (context) => CategoryDialog(
        type: type,
        existing: existing,
        categories: ledger.categoriesFor(type),
      ),
    );
    if (category == null || !mounted) return;
    await persist(
      ledger.copyWith(
        categories: existing == null
            ? [...ledger.categories, category]
            : ledger.categories
                  .map((c) => c.id == existing.id ? category : c)
                  .toList(),
      ),
    );
  }

  Future<void> remove(LedgerCategory category) async {
    final alternatives = ledger
        .categoriesFor(category.type)
        .where((c) => c.id != category.id)
        .toList();
    if (alternatives.isEmpty) {
      showMessage(context, '每种收支至少保留一个分类');
      return;
    }
    final count = ledger.entries
        .where((e) => e.type != EntryType.transfer && e.category == category.id)
        .length;
    String replacement = alternatives.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('删除“${category.name}”？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count == 0 ? '此分类暂无账单，删除后可重新添加。' : '此分类有 $count 笔账单，请选择迁入分类。',
              ),
              if (count > 0) ...[
                const SizedBox(height: 16),
                WalletSelectField(
                  label: '账单迁入分类',
                  value: alternatives
                      .firstWhere((c) => c.id == replacement)
                      .name,
                  icon: Icons.drive_file_move_outlined,
                  onTap: () async {
                    final value = await showWalletChoices<String>(
                      context,
                      title: '选择迁入分类',
                      selected: replacement,
                      options: alternatives
                          .map(
                            (c) => WalletOption(
                              c.id,
                              c.name,
                              icon: categoryIcon(c.icon),
                            ),
                          )
                          .toList(),
                    );
                    if (value != null && context.mounted) {
                      setDialogState(() => replacement = value);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除分类'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await persist(
        ledger.removeCategory(
          category.id,
          replacementId: count > 0 ? replacement : null,
        ),
      );
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final visible = ledger.categoriesFor(type);
    if (newIndex == oldIndex) return;
    final item = visible.removeAt(oldIndex);
    visible.insert(newIndex, item);
    final iterator = visible.iterator;
    final categories = ledger.categories.map((c) {
      if (c.type != type) return c;
      iterator.moveNext();
      return iterator.current;
    }).toList();
    await persist(ledger.copyWith(categories: categories));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ledger.categoriesFor(type);
    final counts = <String, int>{};
    for (final entry in ledger.entries.where(
      (e) => e.type != EntryType.transfer,
    )) {
      counts.update(entry.category, (value) => value + 1, ifAbsent: () => 1);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('分类管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: saving ? null : edit,
        icon: const Icon(Icons.add),
        label: const Text('添加分类'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
              child: WalletSegments<EntryType>(
                options: const [
                  WalletOption(EntryType.expense, '支出分类'),
                  WalletOption(EntryType.income, '收入分类'),
                ],
                selected: type,
                onChanged: saving
                    ? null
                    : (value) => setState(() => type = value),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '拖动右侧手柄排序 · 点击分类修改名称和图标',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            if (saving) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                buildDefaultDragHandles: false,
                itemCount: categories.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (!saving) reorder(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return Padding(
                    key: ValueKey(category.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: panel(
                      ListTile(
                        leading: Icon(
                          categoryIcon(category.icon),
                          color: forest,
                        ),
                        title: Text(category.name),
                        subtitle: Text('${counts[category.id] ?? 0} 笔账单'),
                        onTap: saving ? null : () => edit(category),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '分类操作',
                              icon: const Icon(Icons.more_horiz_rounded),
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final action =
                                          await showWalletChoices<String>(
                                            context,
                                            title: category.name,
                                            selected: '',
                                            options: [
                                              const WalletOption(
                                                'edit',
                                                '编辑',
                                                icon: Icons.edit_outlined,
                                              ),
                                              if (index > 0)
                                                const WalletOption(
                                                  'up',
                                                  '上移',
                                                  icon: Icons
                                                      .arrow_upward_rounded,
                                                ),
                                              if (index < categories.length - 1)
                                                const WalletOption(
                                                  'down',
                                                  '下移',
                                                  icon: Icons
                                                      .arrow_downward_rounded,
                                                ),
                                              const WalletOption(
                                                'delete',
                                                '删除',
                                                icon: Icons
                                                    .delete_outline_rounded,
                                              ),
                                            ],
                                          );
                                      if (!mounted) return;
                                      switch (action) {
                                        case 'edit':
                                          edit(category);
                                        case 'delete':
                                          remove(category);
                                        case 'up':
                                          reorder(index, index - 1);
                                        case 'down':
                                          reorder(index, index + 1);
                                      }
                                    },
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              enabled: !saving,
                              child: const SizedBox(
                                width: 40,
                                height: 48,
                                child: Tooltip(
                                  message: '拖动排序',
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryDialog extends StatefulWidget {
  const CategoryDialog({
    super.key,
    required this.type,
    required this.categories,
    this.existing,
  });
  final EntryType type;
  final List<LedgerCategory> categories;
  final LedgerCategory? existing;
  @override
  State<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<CategoryDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late String icon = categoryIcons.containsKey(widget.existing?.icon)
      ? widget.existing!.icon
      : '其他';
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '添加分类' : '编辑分类'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              maxLength: 24,
              autofocus: true,
              decoration: const InputDecoration(labelText: '分类名称'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return '请输入名称';
                if (widget.categories.any(
                  (c) => c.name == text && c.id != widget.existing?.id,
                )) {
                  return '此名称已存在';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: categoryIcons.entries
                  .where((e) => e.key != '转账')
                  .map(
                    (entry) => WalletPill(
                      label: entry.key,
                      icon: entry.value,
                      selected: icon == entry.key,
                      onTap: () => setState(() => icon = entry.key),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            LedgerCategory(
              id:
                  widget.existing?.id ??
                  'category-${DateTime.now().microsecondsSinceEpoch}',
              name: name.text.trim(),
              type: widget.type,
              icon: icon,
            ),
          );
        },
        child: const Text('保存分类'),
      ),
    ],
  );
}

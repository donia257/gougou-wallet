import 'package:flutter/material.dart';
import 'ledger.dart';
import 'category_rules.dart';
import 'receipt_parser.dart';
import 'selection_ui.dart';
import 'ui.dart';

class ReceiptDraft {
  const ReceiptDraft({
    required this.cents,
    required this.type,
    required this.categoryId,
    required this.note,
    this.date,
  });
  final int cents;
  final EntryType type;
  final String categoryId, note;
  final DateTime? date;
}

class ReceiptReviewPage extends StatefulWidget {
  const ReceiptReviewPage({
    super.key,
    required this.document,
    required this.ledger,
    required this.suggestion,
    required this.currentDate,
    this.currentNote = '',
  });
  final OcrDocument document;
  final Ledger ledger;
  final ReceiptSuggestion suggestion;
  final DateTime currentDate;
  final String currentNote;
  @override
  State<ReceiptReviewPage> createState() => _ReceiptReviewPageState();
}

class _ReceiptReviewPageState extends State<ReceiptReviewPage> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.suggestion.cents == null
        ? ''
        : money(widget.suggestion.cents!),
  );
  late final note = TextEditingController(
    text: widget.suggestion.note.isEmpty
        ? widget.currentNote
        : widget.suggestion.note,
  );
  late EntryType type = widget.suggestion.type ?? EntryType.expense;
  late String category = widget.suggestion.categoryId;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void apply() {
    if (widget.suggestion.blockedReason != null ||
        !form.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      ReceiptDraft(
        cents: parseMoney(amount.text),
        type: type,
        categoryId: category,
        note: note.text.trim(),
        date: widget.suggestion.date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.suggestion;
    int? cents;
    try {
      cents = parseMoney(amount.text);
    } on FormatException {
      /* User is typing. */
    }
    final date = suggestion.date ?? widget.currentDate;
    final duplicate =
        cents != null &&
        widget.ledger.entries.any(
          (e) =>
              e.type == type &&
              e.cents == cents &&
              dayKey(e.date) == dayKey(date),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('核对图片账单')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            sectionTitle('看清这一笔，再填入'),
            const SizedBox(height: 10),
            const Text(
              '图片在本机识别，结果尚未保存。金额与分类是建议，请核对后填入记账页；账户保持原值。',
              style: TextStyle(color: muted, height: 1.7),
            ),
            if (suggestion.blockedReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  suggestion.blockedReason!,
                  style: const TextStyle(color: coral, height: 1.7),
                ),
              ),
            const SizedBox(height: 20),
            WalletSegments<EntryType>(
              selected: type,
              options: const [
                WalletOption(EntryType.expense, '支出'),
                WalletOption(EntryType.income, '收入'),
              ],
              onChanged: (value) => setState(() {
                type = value;
                category = recommendCategory(
                  widget.ledger,
                  value,
                  widget.document.text,
                );
              }),
            ),
            if (suggestion.type == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('未确定收支类型，请手动核对。', style: TextStyle(color: coral)),
              ),
            const SizedBox(height: 18),
            TextFormField(
              key: const ValueKey('ocr-review-amount'),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '识别金额（可修改）',
                prefixText: '¥ ',
              ),
              validator: (value) {
                try {
                  if (parseMoney(value ?? '') <= 0) return '请输入大于零的金额';
                } on FormatException catch (error) {
                  return error.message.toString();
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            if (suggestion.amounts.isEmpty)
              const Text('没有找到可靠金额，请参照原图填写。', style: TextStyle(color: coral))
            else ...[
              const Text(
                '图片中的金额候选 · 实付优先，优惠与余额仅供核对',
                style: TextStyle(color: muted, fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final candidate in suggestion.amounts)
                    Tooltip(
                      message: candidate.evidence,
                      child: ChoiceChip(
                        label: Text('¥ ${money(candidate.cents)}'),
                        selected: cents == candidate.cents,
                        onSelected: (_) => setState(
                          () => amount.text = money(candidate.cents),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (duplicate)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '账本已有同一天、同类型、同金额的记录，请留意是否重复记账。',
                  style: TextStyle(color: coral, height: 1.7),
                ),
              ),
            const SizedBox(height: 18),
            WalletSelectField(
              label: '推荐分类（可修改）',
              value: widget.ledger.categoryById(category).name,
              icon: Icons.category_outlined,
              onTap: () async {
                final result = await showWalletChoices<String>(
                  context,
                  title: '核对分类',
                  selected: category,
                  options: widget.ledger
                      .categoriesFor(type)
                      .map(
                        (c) => WalletOption(
                          c.id,
                          c.name,
                          icon: categoryIcon(c.icon),
                        ),
                      )
                      .toList(),
                );
                if (result != null && mounted) {
                  setState(() => category = result);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              suggestion.date == null
                  ? '未识别到日期，沿用记账页的日期和时间。'
                  : '交易时间：${dayKey(date)} ${timeLabel(date)}\n可在记账页继续修改日期与时间。',
              style: const TextStyle(color: muted, height: 1.7),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('ocr-review-note'),
              controller: note,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '商户 / 备注（可修改）'),
            ),
            const SizedBox(height: 12),
            panel(
              ExpansionTile(
                title: const Text('查看识别原文'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  SelectableText(
                    widget.document.text.isEmpty
                        ? widget.document.lines.map((l) => l.text).join('\n')
                        : widget.document.text,
                    style: const TextStyle(color: muted, height: 1.7),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
          child: FilledButton(
            onPressed: suggestion.blockedReason == null ? apply : null,
            child: const Text('填入记账页'),
          ),
        ),
      ),
    );
  }
}

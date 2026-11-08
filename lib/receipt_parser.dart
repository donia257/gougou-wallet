import 'ledger.dart';
import 'category_rules.dart';

class OcrLine {
  const OcrLine(
    this.text, {
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });
  final String text;
  final int left, top, right, bottom;
  int get height => bottom - top;
}

class OcrDocument {
  const OcrDocument(this.text, this.lines);
  factory OcrDocument.fromMap(Map<Object?, Object?> data) =>
      OcrDocument(data['text'] as String? ?? '', [
        for (final raw in data['lines'] as List? ?? [])
          OcrLine(
            (raw as Map)['text'] as String? ?? '',
            left: raw['left'] as int? ?? 0,
            top: raw['top'] as int? ?? 0,
            right: raw['right'] as int? ?? 0,
            bottom: raw['bottom'] as int? ?? 0,
          ),
      ]);
  final String text;
  final List<OcrLine> lines;
}

class ReceiptAmount {
  const ReceiptAmount(this.cents, this.evidence, this.score);
  final int cents, score;
  final String evidence;
}

class ReceiptSuggestion {
  const ReceiptSuggestion({
    required this.amounts,
    required this.type,
    required this.categoryId,
    required this.note,
    this.date,
    this.blockedReason,
  });
  final List<ReceiptAmount> amounts;
  final EntryType? type;
  final String categoryId, note;
  final DateTime? date;
  final String? blockedReason;
  int? get cents => amounts.isNotEmpty && amounts.first.score >= 40
      ? amounts.first.cents
      : null;
}

final _amountPattern = RegExp(
  r'(?<![\d.．])([+-]?)\s*([¥￥]?)\s*((?:\d{1,3}(?:[,，]\d{3})+|\d{1,9})(?:[.．]\d{1,2})?)\s*(元?)(?![\d.．])',
);
final _strongAmount = RegExp(
  '实付款|实付金额|实际支付|实际付款|支付金额|付款金额|消费金额|交易金额|收款金额|到账金额|实收|实付',
);
final _totalAmount = RegExp('合计|总计|应付|应收|总额');
final _excludedAmount = RegExp('优惠|原价|找零|立减|抵扣|折扣|积分|余额|手续费|单价|数量|红包抵');
final _datePattern = RegExp(
  r'\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?(?:[ T\s]+\d{1,2}:\d{2}(?::\d{2})?)?',
);

/// Rules only suggest values. The review/editor remains the only path to saving.
ReceiptSuggestion parseReceipt(OcrDocument document, Ledger ledger) {
  final lines = document.lines.isEmpty
      ? document.text.split('\n').map(OcrLine.new).toList()
      : document.lines;
  final text = document.text.isEmpty
      ? lines.map((l) => l.text).join('\n')
      : document.text;
  final blocked =
      RegExp(
        '退款成功|退款金额|已全额退款|已退款|部分退款|退款详情|转账详情|转账成功|转账给|提现成功|充值成功|还款成功|待支付|待付款|交易关闭|支付失败|付款失败|订单关闭',
      ).hasMatch(text) ||
      lines.any((l) => l.text.trim() == '转账');
  final EntryType? type = RegExp('收款成功|已收款|收款金额|到账金额|收入金额').hasMatch(text)
      ? EntryType.income
      : RegExp('支付成功|付款成功|消费|实付|合计|总计|小票|欢迎光临').hasMatch(text)
      ? EntryType.expense
      : null;
  final amounts = <int, ReceiptAmount>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final own = line.text;
    if (_datePattern.hasMatch(own) && !_strongAmount.hasMatch(own)) continue;
    var label = own;
    // OCR often separates labels and values into different blocks. Geometry
    // allows matching the label to the left rather than relying on block order.
    if (!_strongAmount.hasMatch(own) && !_totalAmount.hasMatch(own)) {
      final sameRow =
          lines
              .where(
                (l) =>
                    l != line &&
                    l.right <= line.left &&
                    line.height > 0 &&
                    (l.top + l.bottom - line.top - line.bottom).abs() <=
                        line.height &&
                    (_strongAmount.hasMatch(l.text) ||
                        _totalAmount.hasMatch(l.text) ||
                        _excludedAmount.hasMatch(l.text)),
              )
              .toList()
            ..sort((a, b) => b.right.compareTo(a.right));
      if (sameRow.isNotEmpty) {
        label = '${sameRow.first.text} $own';
      } else if (i > 0 &&
          (_strongAmount.hasMatch(lines[i - 1].text) ||
              _totalAmount.hasMatch(lines[i - 1].text) ||
              _excludedAmount.hasMatch(lines[i - 1].text)) &&
          !_amountPattern
              .allMatches(lines[i - 1].text)
              .any(
                (m) => m.group(2)!.isNotEmpty || m.group(3)!.contains('.'),
              ) &&
          (line.height == 0 ||
              (line.top - lines[i - 1].bottom).abs() < line.height * 4)) {
        label = '${lines[i - 1].text} $own';
      }
    }
    for (final match in _amountPattern.allMatches(own)) {
      final raw = match.group(3)!;
      final marked = match.group(2)!.isNotEmpty || match.group(4)!.isNotEmpty;
      if (!marked &&
          !raw.contains('.') &&
          !raw.contains('．') &&
          !_strongAmount.hasMatch(label) &&
          !_totalAmount.hasMatch(label)) {
        continue;
      }
      // A decimal on an order/transaction number line is not a price.
      if (RegExp('订单号|交易单号|交易号|商户单号|手机号|电话|卡号').hasMatch(own)) continue;
      try {
        final cents = parseMoney(
          raw.replaceAll(RegExp('[,，]'), '').replaceAll('．', '.'),
        );
        if (cents <= 0) continue;
        final labelTokens = RegExp(
          '${_strongAmount.pattern}|${_totalAmount.pattern}|${_excludedAmount.pattern}',
        ).allMatches(own.substring(0, match.start)).toList();
        final effectiveLabel = labelTokens.isEmpty
            ? label
            : labelTokens.last.group(0)!;
        var score = _strongAmount.hasMatch(effectiveLabel)
            ? 130
            : _totalAmount.hasMatch(effectiveLabel)
            ? 95
            : marked
            ? 65
            : 40;
        if (_excludedAmount.hasMatch(effectiveLabel) &&
            !RegExp('实付|实际支付|实际付款|实收').hasMatch(effectiveLabel)) {
          score -= 150;
        }
        // Multiple values on one line without a clear label remain alternatives.
        if (_amountPattern.allMatches(own).length > 1) score -= 20;
        final candidate = ReceiptAmount(cents, label.trim(), score);
        if (!amounts.containsKey(cents) || amounts[cents]!.score < score) {
          amounts[cents] = candidate;
        }
      } on FormatException {
        /* Invalid precision/amount is never coerced. */
      }
    }
  }
  final ranked = amounts.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  final merchant = _merchant(lines);
  DateTime? date;
  final ordered = [...lines]
    ..sort(
      (a, b) =>
          (RegExp('交易时间|支付时间|付款时间|收款时间').hasMatch(b.text) ? 1 : 0) -
          (RegExp('交易时间|支付时间|付款时间|收款时间').hasMatch(a.text) ? 1 : 0),
    );
  for (final line in ordered) {
    final match = _datePattern.firstMatch(line.text);
    if (match == null) continue;
    date = parseTransactionDate(match.group(0)!, dateOnly: true);
    if (date != null) break;
  }
  final categoryType = type ?? EntryType.expense;
  final merchantCategory = recommendCategory(ledger, categoryType, merchant);
  final category = merchantCategory == fallbackCategory(ledger, categoryType)
      ? recommendCategory(ledger, categoryType, text)
      : merchantCategory;
  return ReceiptSuggestion(
    amounts: List.unmodifiable(ranked.take(12)),
    type: type,
    categoryId: category,
    note: String.fromCharCodes(merchant.runes.take(120)),
    date: date,
    blockedReason: blocked ? '这张图片包含退款、转账或未完成交易，请返回记账页人工核对收支类型与金额。' : null,
  );
}

String _merchant(List<OcrLine> lines) {
  final label = RegExp(
    r'^(?:收款方|商户名称|商家名称|收款商户|交易对方|商户|商家|付款方|付款人)\s*[:：]?\s*(.*)$',
  );
  bool usable(String text) =>
      text.length >= 2 &&
      text.length <= 80 &&
      !RegExp(r'^[\d\s¥￥.,:+\-/%]+$').hasMatch(text) &&
      !_datePattern.hasMatch(text) &&
      !RegExp('交易时间|订单号|交易单号|交易号|支付方式|付款方式|支付成功|收款成功').hasMatch(text);
  for (var i = 0; i < lines.length; i++) {
    final match = label.firstMatch(lines[i].text.trim());
    if (match == null) continue;
    final value = match.group(1)!.trim();
    if (usable(value)) return value;
    // Handle a label/value pair laid out in separate OCR blocks.
    final line = lines[i];
    final paired = lines
        .where(
          (l) =>
              l.left >= line.right &&
              line.height > 0 &&
              (l.top + l.bottom - line.top - line.bottom).abs() <=
                  line.height &&
              usable(l.text.trim()),
        )
        .toList();
    if (paired.isNotEmpty) return paired.first.text.trim();
    if (i + 1 < lines.length && usable(lines[i + 1].text.trim())) {
      return lines[i + 1].text.trim();
    }
  }
  for (final line in lines.take(10)) {
    final text = line.text.trim();
    if (!usable(text) ||
        RegExp(
          '微信|支付宝|账单|详情|扫一扫|收银|合计|总计|实付|原价|优惠|余额|返回|完成|付款|收款|欢迎光临',
        ).hasMatch(text) ||
        _amountPattern
            .allMatches(text)
            .any((m) => m.group(2)!.isNotEmpty || m.group(4)!.isNotEmpty)) {
      continue;
    }
    return text;
  }
  return '';
}

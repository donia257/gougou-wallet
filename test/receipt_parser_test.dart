import 'package:daily_ledger/receipt_parser.dart';
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/category_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const paymentText =
    '12:34\n微信支付\n支付成功\n￥28.50\n收款方\n星巴克咖啡\n支付时间\n2026-11-08 12:30:00\n原价 ￥35.00\n优惠 ￥6.50';
OcrDocument receipt(String text) => OcrDocument(text, const []);

void main() {
  test(
    'separated discount labels and mixed amount lines do not outrank paid amount',
    () {
      final result = parseReceipt(
        const OcrDocument('支付成功\n￥28.50\n原价\n优惠\n￥35.00\n￥6.50', [
          OcrLine('支付成功'),
          OcrLine('￥28.50', left: 200, top: 40, right: 400, bottom: 80),
          OcrLine('原价', left: 10, top: 120, right: 100, bottom: 150),
          OcrLine('优惠', left: 10, top: 200, right: 100, bottom: 230),
          OcrLine('￥35.00', left: 300, top: 120, right: 450, bottom: 150),
          OcrLine('￥6.50', left: 300, top: 200, right: 450, bottom: 230),
        ]),
        Ledger.empty(),
      );
      expect(result.cents, 2850);
      expect(parseReceipt(receipt('优惠后实付 ￥28.50'), Ledger.empty()).cents, 2850);
      expect(
        parseReceipt(receipt('实付款￥28.50 优惠￥6.50'), Ledger.empty()).cents,
        2850,
      );
    },
  );
  test(
    'payment screenshot prioritizes paid amount, extracts merchant, date and category',
    () {
      final result = parseReceipt(receipt(paymentText), Ledger.empty());
      expect(result.cents, 2850);
      expect(result.type, EntryType.expense);
      expect(result.note, '星巴克咖啡');
      expect(result.date, DateTime(2026, 11, 8, 12, 30));
      expect(result.categoryId, 'expense-0');
      expect(
        result.amounts.map((a) => a.cents),
        containsAll([2850, 3500, 650]),
      );
      expect(result.blockedReason, isNull);
    },
  );

  test(
    'spatial labels bind to the correct same-row amount across OCR blocks',
    () {
      final result = parseReceipt(
        const OcrDocument('支付成功\n实付款\n原价￥68.00\n￥58.00', [
          OcrLine('支付成功'),
          OcrLine('实付款', left: 10, top: 100, right: 100, bottom: 130),
          OcrLine('原价￥68.00', left: 10, top: 160, right: 180, bottom: 190),
          OcrLine('￥58.00', left: 300, top: 100, right: 450, bottom: 130),
        ]),
        Ledger.empty(),
      );
      expect(result.cents, 5800);
    },
  );

  test(
    'Alipay receipt and shop receipt prefer actual payment over totals and discounts',
    () {
      final result = parseReceipt(
        receipt('瑞幸咖啡\n付款成功\n实付款\n¥18.90\n合计25.00元\n优惠6.10元\n申请退款'),
        Ledger.empty(),
      );
      expect(result.cents, 1890);
      expect(result.note, '瑞幸咖啡');
      expect(result.blockedReason, isNull);
      expect(
        parseReceipt(
          receipt('便利店\n欢迎光临\n单价5.00\n数量2\n合计10.00元\n找零90.00元'),
          Ledger.empty(),
        ).cents,
        1000,
      );
    },
  );

  test(
    'income and existing custom categories reuse category rules with stable IDs',
    () {
      final result = parseReceipt(
        receipt('收款成功\n到账金额 ￥5,000.00\n交易对方 某公司\n商品说明 工资'),
        Ledger.empty(),
      );
      expect(result.cents, 500000);
      expect(result.type, EntryType.income);
      expect(result.categoryId, 'income-0');
      final ledger = Ledger.empty().copyWith(
        categories: [
          ...Ledger.empty().categories,
          const LedgerCategory(
            id: 'coffee',
            name: '咖啡',
            type: EntryType.expense,
            icon: '餐饮',
          ),
        ],
      );
      expect(recommendCategory(ledger, EntryType.expense, '星巴克咖啡'), 'coffee');
    },
  );

  test(
    'dates, times, identifiers and excessive precision are never treated as prices',
    () {
      for (final text in [
        '订单号 123456789012345678\n2026-11-08 12:34:56',
        '交易单号 123.45',
        '电话 13800138000',
        '金额 ￥12.301',
        '￥0.00',
        '优惠券 ￥30.00',
      ]) {
        expect(
          parseReceipt(receipt(text), Ledger.empty()).cents,
          isNull,
          reason: text,
        );
      }
      final result = parseReceipt(
        receipt('支付成功\n￥10\n2026-02-31 12:34'),
        Ledger.empty(),
      );
      expect(result.cents, 1000);
      expect(result.date, isNull);
      expect(
        parseTransactionDate('2026年11月08日 12:34', dateOnly: true),
        DateTime(2026, 11, 8, 12, 34),
      );
      expect(parseTransactionDate('2026-11-08 25:01'), isNull);
    },
  );

  test(
    'refunds, transfers and unfinished payments are explicitly blocked from applying',
    () {
      for (final state in [
        '退款成功',
        '已退款',
        '转账成功',
        '转账',
        '提现成功',
        '待付款',
        '支付失败',
      ]) {
        expect(
          parseReceipt(receipt('$state\n￥25.00'), Ledger.empty()).blockedReason,
          isNotNull,
          reason: state,
        );
      }
    },
  );

  test(
    'unknown category falls back and duplicate amount candidates are collapsed',
    () {
      final result = parseReceipt(
        receipt('支付成功\n实付款￥20.00\n交易金额￥20.00'),
        Ledger.empty(),
      );
      expect(result.amounts.length, 1);
      expect(
        result.categoryId,
        fallbackCategory(Ledger.empty(), EntryType.expense),
      );
    },
  );
}

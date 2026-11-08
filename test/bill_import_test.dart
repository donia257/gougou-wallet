import 'dart:convert';
import 'package:daily_ledger/bill_import.dart';
import 'package:daily_ledger/ledger.dart';
import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

const wechatHeader = '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注';
const alipayHeader =
    '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注';
const wechatRow =
    '2026-11-08 12:30:00,商户消费,便利店,午餐,支出,￥12.30,零钱,支付成功,420000000000000000001,abc,备注';
const alipayRow =
    '2026-11-08 09:01:02,餐饮美食,早餐店,a***,豆浆,支出,3.50,余额,交易成功,20261108000000000001,abc,备注';

ImportPreview wx(String rows, [Ledger? ledger]) => parseBillFile(
  utf8.encode('微信支付账单明细\r\n统计时间：2026-11\r\n$wechatHeader\r\n$rows\r\n'),
  '微信.csv',
  ledger ?? Ledger.empty(),
);

Ledger apply(Ledger ledger, ImportPreview preview, {DateTime? now}) =>
    applyBillImport(
      ledger,
      preview,
      preview.rows
          .where((r) => r.disposition == ImportDisposition.ready)
          .map((r) => r.line)
          .toSet(),
      'wechat',
      {
        for (final r in preview.rows.where((r) => r.selectable))
          r.line: r.type == EntryType.income ? 'income-0' : 'expense-0',
      },
      now: now,
    );

void main() {
  test(
    'large import and undo preserve 10000 existing and 5000 new transactions',
    () {
      final base = Ledger.empty().copyWith(
        entries: [
          for (var i = 0; i < 10000; i++)
            LedgerEntry(
              id: 'manual-$i',
              type: EntryType.expense,
              cents: 100,
              date: DateTime(2026, 11, 1, 10),
              category: 'expense-0',
              accountId: 'cash',
            ),
        ],
      );
      final data = [
        for (var i = 0; i < 5000; i++)
          wechatRow.replaceFirst('420000000000000000001', 'trade-$i'),
      ].join('\n');
      final watch = Stopwatch()..start();
      final preview = wx(data, base);
      final parseMs = watch.elapsedMilliseconds;
      final imported = apply(base, preview);
      final restored = Ledger.decode(imported.encode());
      expect(restored.entries.length, 15000);
      expect(restored.balance('wechat'), -6150000);
      expect(
        wx(
          data,
          restored,
        ).rows.every((r) => r.disposition == ImportDisposition.duplicate),
        isTrue,
      );
      final undone = undoBillImport(restored, restored.importBatches.single.id);
      expect(undone.encode(), base.encode());
      // Recorded as host measurements, not device performance guarantees.
      // ignore: avoid_print
      print(
        'Import benchmark: preview=${parseMs}ms, full roundtrip=${watch.elapsedMilliseconds}ms',
      );
    },
  );

  test(
    'legacy Alipay columns recognize refunded amount and damaged numeric IDs',
    () {
      const header =
          '交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态';
      const row =
          '20261108001,abc,2026-11-08 12:30:00,,,,消费,便利店,午餐,12.30,支出,交易成功,0.00,0.00,备注,已支出';
      final valid = parseBillFile(
        gbk.encode('$header\n$row'),
        'alipay-old.csv',
        Ledger.empty(),
      );
      expect(valid.rows.single.disposition, ImportDisposition.ready);
      final refund = parseBillFile(
        gbk.encode('$header\n${row.replaceFirst('0.00,0.00', '0.00,2.00')}'),
        'refund.csv',
        Ledger.empty(),
      );
      expect(refund.rows.single.disposition, ImportDisposition.excluded);
      expect(
        wx(
          wechatRow.replaceFirst('420000000000000000001', '4.2E+20'),
        ).rows.single.disposition,
        ImportDisposition.invalid,
      );
    },
  );
  test(
    'CSV quoting handles newlines, commas, quotes, CRLF and rejects truncation',
    () {
      expect(parseDelimited('a,"b,c","d""e"\r\n1,"two\nlines",3', ','), [
        ['a', 'b,c', 'd"e'],
        ['1', 'two\nlines', '3'],
      ]);
      expect(() => parseDelimited('a,"b', ','), throwsFormatException);
      expect(() => parseDelimited('a,"b"bad', ','), throwsFormatException);
    },
  );

  test(
    'WeChat UTF8 BOM, preamble and quoted descriptions retain exact IDs and cents',
    () {
      final preview = parseBillFile(
        utf8.encode(
          '\uFEFF微信支付账单\n$wechatHeader\n'
          '${wechatRow.replaceFirst('午餐', '"午餐,含饮料\n第二行"')}\n',
        ),
        'wx.csv',
        Ledger.empty(),
      );
      expect(preview.platform, '微信');
      expect(preview.rows.single.cents, 1230);
      expect(preview.rows.single.date, DateTime(2026, 11, 8, 12, 30));
      expect(preview.rows.single.sourceKey, '微信:id:420000000000000000001');
      expect(preview.rows.single.description, contains('午餐,含饮料\n第二行'));
    },
  );

  test(
    'Alipay GBK CSV and tab-separated exports use the same trade identity',
    () {
      final csv = '支付宝交易记录\n$alipayHeader\n$alipayRow\n';
      final preview = parseBillFile(gbk.encode(csv), '支付宝.csv', Ledger.empty());
      final tabs = parseBillFile(
        utf8.encode(csv.replaceAll(',', '\t')),
        '支付宝.csv',
        Ledger.empty(),
      );
      expect(preview.platform, '支付宝');
      expect(preview.rows.single.cents, 350);
      expect(tabs.rows.single.sourceKey, preview.rows.single.sourceKey);
    },
  );

  test(
    'WeChat and Alipay XLSX recognize text IDs, amount and Excel date cells',
    () {
      for (final source in ['微信', '支付宝']) {
        final excel = Excel.createExcel();
        final sheet = excel['Sheet1'];
        final header = source == '微信' ? wechatHeader : alipayHeader;
        final row = source == '微信' ? wechatRow : alipayRow;
        sheet.appendRow([TextCellValue('导出的交易流水')]);
        sheet.appendRow(header.split(',').map(TextCellValue.new).toList());
        final cells = row.split(',').map<CellValue>(TextCellValue.new).toList();
        cells[0] = DateTimeCellValue(
          year: 2026,
          month: 11,
          day: 8,
          hour: 12,
          minute: 30,
        );
        sheet.appendRow(cells);
        final preview = parseBillFile(
          excel.encode()!,
          '$source.xlsx',
          Ledger.empty(),
        );
        expect(preview.platform, source);
        expect(preview.rows.single.date, DateTime(2026, 11, 8, 12, 30));
        expect(preview.rows.single.disposition, ImportDisposition.ready);
      }
    },
  );

  test(
    'refunds, pending, asset movement, unknown status and invalid money are explicit',
    () {
      final preview = wx(
        [
          wechatRow,
          wechatRow.replaceFirst('支付成功', '已全额退款'),
          wechatRow.replaceFirst('支付成功', '交易关闭'),
          wechatRow.replaceFirst('支出', '/'),
          wechatRow.replaceFirst('商户消费', '零钱提现'),
          wechatRow.replaceFirst('支付成功', '未知状态'),
          wechatRow.replaceFirst('￥12.30', '12.301'),
          wechatRow.replaceFirst('2026-11-08', '2026-02-31'),
          wechatRow.replaceFirst('￥12.30', '-12'),
          wechatRow.replaceFirst('￥12.30', '0'),
        ].join('\n'),
      );
      expect(preview.rows.map((r) => r.disposition), [
        ImportDisposition.ready,
        ImportDisposition.excluded,
        ImportDisposition.excluded,
        ImportDisposition.excluded,
        ImportDisposition.excluded,
        ImportDisposition.invalid,
        ImportDisposition.invalid,
        ImportDisposition.invalid,
        ImportDisposition.invalid,
        ImportDisposition.excluded,
      ]);
      expect(
        () => parseBillFile(utf8.encode('乱码'), 'invalid.csv', Ledger.empty()),
        throwsFormatException,
      );
      expect(
        () => parseBillFile([], 'empty.csv', Ledger.empty()),
        throwsFormatException,
      );
    },
  );

  test(
    'same file, overlaps and changed descriptions deduplicate by platform + trade ID',
    () {
      final first = wx('$wechatRow\n$wechatRow');
      expect(first.rows.last.disposition, ImportDisposition.duplicate);
      final imported = apply(Ledger.empty(), first);
      final repeated = wx(wechatRow.replaceFirst('午餐', '新备注'), imported);
      expect(repeated.rows.single.disposition, ImportDisposition.duplicate);
      expect(imported.balance('wechat'), -1230);
      final otherPlatform = parseBillFile(
        utf8.encode(
          '$alipayHeader\n'
          '${alipayRow.replaceFirst('20261108000000000001', '420000000000000000001')}',
        ),
        'alipay.csv',
        imported,
      );
      expect(otherPlatform.rows.single.disposition, ImportDisposition.ready);
    },
  );

  test(
    'manual overlaps require review, missing IDs retain identical legitimate transactions',
    () {
      final original = apply(Ledger.empty(), wx(wechatRow)).entries.single;
      final manual = LedgerEntry(
        id: 'manual',
        type: original.type,
        cents: original.cents,
        date: original.date,
        category: original.category,
        accountId: original.accountId,
      );
      expect(
        wx(
          wechatRow,
          Ledger.empty().copyWith(entries: [manual]),
        ).rows.single.disposition,
        ImportDisposition.review,
      );
      final missing = wechatRow.replaceFirst('420000000000000000001', '/');
      final preview = wx('$missing\n$missing');
      expect(
        preview.rows.every((r) => r.disposition == ImportDisposition.review),
        isTrue,
      );
      expect(preview.rows.map((r) => r.sourceKey).toSet().length, 2);
    },
  );

  test(
    'undo preserves later manual, copied, other batches, budget and categories after backup',
    () {
      final base = Ledger.empty().copyWith(budgets: {'2026-11': 50000});
      final first = apply(base, wx(wechatRow), now: DateTime(2026, 11, 8, 12));
      final firstBatch = first.importBatches.single;
      final imported = first.entries.single;
      final edited = LedgerEntry(
        id: imported.id,
        type: imported.type,
        cents: 2000,
        date: imported.date,
        category: imported.category,
        accountId: imported.accountId,
        note: '已修改',
        importBatchId: imported.importBatchId,
        sourceKey: imported.sourceKey,
      );
      final manual = LedgerEntry(
        id: 'copy',
        type: imported.type,
        cents: 99,
        date: imported.date,
        category: imported.category,
        accountId: 'cash',
      );
      final second = apply(
        first.copyWith(entries: [edited, manual]),
        wx(wechatRow.replaceFirst('420000000000000000001', 'second-id')),
        now: DateTime(2026, 11, 8, 13),
      );
      final restored = Ledger.decode(second.encode());
      expect(restored.encode(), second.encode());
      expect(
        entryFingerprint(edited),
        isNot(firstBatch.fingerprints[edited.id]),
      );
      final undone = undoBillImport(restored, firstBatch.id);
      expect(undone.entries.map((e) => e.id), contains('copy'));
      expect(undone.entries.length, 2);
      expect(undone.balance('wechat'), -1230);
      expect(undone.balance('cash'), -99);
      expect(undone.budgets, base.budgets);
      expect(
        undone.categories.map((c) => c.toJson()).toList(),
        base.categories.map((c) => c.toJson()).toList(),
      );
      expect(undone.importBatches.length, 1);
      expect(
        wx(wechatRow, undone).rows.single.disposition,
        ImportDisposition.review,
      );
      expect(
        () => undoBillImport(undone, firstBatch.id),
        throwsFormatException,
      );
    },
  );

  test(
    'deleted imported entry remains deduplicated until its batch is undone',
    () {
      final imported = apply(Ledger.empty(), wx(wechatRow));
      final deleted = imported.copyWith(entries: []);
      deleted.validate();
      expect(
        wx(wechatRow, deleted).rows.single.disposition,
        ImportDisposition.duplicate,
      );
      final undone = undoBillImport(deleted, imported.importBatches.single.id);
      expect(
        wx(wechatRow, undone).rows.single.disposition,
        ImportDisposition.ready,
      );
    },
  );

  test(
    'v2 backup migration and v3 metadata validation reject orphaned associations',
    () {
      final v2 = Ledger.empty().toJson()
        ..['version'] = 2
        ..remove('importBatches');
      expect(Ledger.decode(jsonEncode(v2)).importBatches, isEmpty);
      final imported = apply(Ledger.empty(), wx(wechatRow));
      expect(
        () => imported.copyWith(importBatches: []).validate(),
        throwsFormatException,
      );
      final json = imported.toJson();
      (json['importBatches'] as List).first['sourceKeys'] = ['微信:id:wrong'];
      expect(() => Ledger.decode(jsonEncode(json)), throwsFormatException);
    },
  );
}

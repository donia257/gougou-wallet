import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'ledger.dart';

enum ImportDisposition { ready, review, duplicate, excluded, invalid }

class ImportRow {
  const ImportRow({
    required this.line,
    required this.description,
    required this.reason,
    required this.disposition,
    this.date,
    this.type,
    this.cents,
    this.sourceKey,
  });
  final int line;
  final String description;
  final String reason;
  final ImportDisposition disposition;
  final DateTime? date;
  final EntryType? type;
  final int? cents;
  final String? sourceKey;
  bool get selectable =>
      disposition == ImportDisposition.ready ||
      disposition == ImportDisposition.review;
}

class ImportPreview {
  const ImportPreview(this.platform, this.fileName, this.rows);
  final String platform;
  final String fileName;
  final List<ImportRow> rows;
}

String entryFingerprint(LedgerEntry entry) => sha256
    .convert(
      utf8.encode(
        jsonEncode(
          entry.toJson()
            ..remove('importBatchId')
            ..remove('sourceKey'),
        ),
      ),
    )
    .toString();

/// Parses RFC 4180 quoting, embedded newlines, and tab-separated exports.
List<List<String>> parseDelimited(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  var closed = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == delimiter) {
      row.add(cell.toString());
      cell = StringBuffer();
      closed = false;
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      rows.add(row);
      row = [];
      cell = StringBuffer();
      closed = false;
    } else if (c == '"' && cell.isEmpty && !closed) {
      quoted = true;
    } else if (closed && c.trim().isNotEmpty) {
      throw const FormatException('CSV 引号后的内容有误');
    } else {
      cell.write(c);
    }
    if (rows.length > 50200 || row.length > 100 || cell.length > 100000) {
      throw const FormatException('账单超过 5 万行或字段过长，请分段导出');
    }
  }
  if (quoted) throw const FormatException('CSV 存在未闭合的引号');
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

String _clean(String value) => value.replaceAll('\uFEFF', '').trim();
String _header(String value) =>
    _clean(value).replaceAll(RegExp(r'[\s（）()]'), '');

String _cellText(Data? data) {
  final value = data?.value;
  if (value is DateTimeCellValue) {
    return value.asDateTimeLocal().toIso8601String();
  }
  if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String();
  if (value is FormulaCellValue) return '[不支持公式单元格]';
  return value?.toString() ?? '';
}

/// Runs in an isolate from the UI; all unrecognized states remain visible.
ImportPreview parseBillFile(List<int> bytes, String fileName, Ledger ledger) {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('请选择非空且不超过 20 MB 的账单文件');
  }
  List<List<List<String>>> tables;
  if (bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    // Bound the uncompressed XLSX before handing it to the workbook decoder.
    validateWorkbookSize(bytes);
    final workbook = Excel.decodeBytes(normalizeWorkbookPaths(bytes));
    tables = [
      for (final sheet in workbook.tables.values)
        [
          for (final row in sheet.rows)
            [for (final cell in row) _cellText(cell)],
        ],
    ];
  } else {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = gbk.decode(bytes);
    }
    // Determine delimiter using the header line, not introductory prose.
    final lines = text.split(RegExp(r'\r?\n'));
    final header = lines.firstWhere(
      (l) =>
          (l.contains('交易时间') || l.contains('交易创建时间')) &&
          (l.contains('收/支') || l.contains('收支')),
      orElse: () => '',
    );
    final delimiter = header.contains('\t') ? '\t' : ',';
    tables = [parseDelimited(text.replaceFirst('\uFEFF', ''), delimiter)];
  }
  for (final table in tables) {
    for (var i = 0; i < table.length && i < 200; i++) {
      final headers = table[i].map(_header).toList();
      if (!(headers.contains('交易时间') || headers.contains('交易创建时间')) ||
          !(headers.contains('收/支') || headers.contains('收支')) ||
          !headers.any((h) => h == '金额元' || h == '金额')) {
        continue;
      }
      final String platform;
      if (headers.contains('交易单号') && headers.contains('当前状态')) {
        platform = '微信';
      } else if ((headers.contains('交易订单号') || headers.contains('交易号')) &&
          headers.contains('交易状态')) {
        platform = '支付宝';
      } else {
        throw const FormatException('无法识别来源，请使用微信或支付宝导出的原始账单');
      }
      if (table.length - i > 50001) {
        throw const FormatException('账单超过 5 万行，请分段导出');
      }
      return _preview(platform, fileName, table, i, headers, ledger);
    }
  }
  throw const FormatException(
    '未找到账单表头，支持微信、支付宝原始 CSV / XLSX 账单，不支持 ZIP 压缩包或旧版 XLS',
  );
}

/// Read the real ZIP directory without inflating entries first.
void validateWorkbookSize(List<int> bytes) {
  final directory = ZipDirectory.read(InputStream(bytes));
  final files = directory.fileHeaders;
  if (files.isEmpty || files.length > 1000) {
    throw const FormatException('XLSX 内容无效或文件数量过多');
  }
  var expanded = 0;
  for (final file in files) {
    expanded += file.uncompressedSize ?? 0;
    if (expanded > 80 * 1024 * 1024) {
      throw const FormatException('XLSX 解压后过大，请分段导出');
    }
  }
}

/// The Excel package assumes workbook relationship targets are relative to xl/.
/// OOXML also permits /xl/... package-absolute targets (e.g. openpyxl exports).
/// Normalize only these legal targets in memory; the original file is untouched.
List<int> normalizeWorkbookPaths(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  const name = 'xl/_rels/workbook.xml.rels';
  final relations = archive.findFile(name);
  if (relations == null) throw const FormatException('XLSX 缺少工作表关联信息');
  final document = XmlDocument.parse(
    utf8.decode(relations.content as List<int>),
  );
  var changed = false;
  for (final node in document.descendants.whereType<XmlElement>()) {
    if (node.name.local != 'Relationship') continue;
    final target = node.getAttribute('Target');
    if (target != null &&
        target.startsWith('/xl/') &&
        node.getAttribute('TargetMode') != 'External') {
      node.setAttribute('Target', target.substring(4));
      changed = true;
    }
  }
  if (!changed) return bytes;
  final content = utf8.encode(document.toXmlString());
  archive.addFile(ArchiveFile(name, content.length, content));
  return ZipEncoder().encode(archive)!;
}

ImportPreview _preview(
  String platform,
  String fileName,
  List<List<String>> table,
  int headerRow,
  List<String> headers,
  Ledger ledger,
) {
  final known = {for (final b in ledger.importBatches) ...b.sourceKeys};
  final seen = <String>{};
  final occurrences = <String, int>{};
  final existing = <String>{
    for (final e in ledger.entries)
      '${e.type.name}|${e.cents}|${e.date.toIso8601String().substring(0, 16)}',
  };
  final rows = <ImportRow>[];
  for (var i = headerRow + 1; i < table.length; i++) {
    final values = table[i];
    if (values.every((v) => v.trim().isEmpty)) continue;
    String field(List<String> names) {
      final index = headers.indexWhere(names.contains);
      return index < 0 || index >= values.length ? '' : _clean(values[index]);
    }

    final dateText = field(['交易时间', '交易创建时间']);
    if (values.first.trim().startsWith('---') ||
        (dateText.isEmpty &&
            values.any((v) => v.contains('共') && v.contains('笔')))) {
      continue;
    }
    final counterpart = field(['交易对方']);
    final product = field(['商品', '商品说明', '商品名称']);
    final note = field(['备注']);
    final description = [
      counterpart,
      product,
      if (note != '/' && note != '-') note,
    ].where((v) => v.isNotEmpty).join(' · ');
    ImportRow rejected(ImportDisposition disposition, String reason) =>
        ImportRow(
          line: i + 1,
          description: description.isEmpty ? dateText : description,
          reason: reason,
          disposition: disposition,
        );
    try {
      final status = field(['当前状态', '交易状态']);
      final direction = field(['收/支', '收支']);
      final kind = field(['交易类型', '交易分类']);
      final refunded = field(['成功退款元', '成功退款']);
      if (refunded.isNotEmpty &&
          refunded != '-' &&
          refunded != '/' &&
          parseMoney(refunded.replaceAll(RegExp(r'[¥￥,\s]'), '')) > 0) {
        rows.add(rejected(ImportDisposition.excluded, '此交易含已退款金额，请核对后手动处理'));
        continue;
      }
      if ([
        status,
        kind,
        product,
      ].any((s) => s.contains('退款') || s.contains('退还'))) {
        rows.add(
          rejected(ImportDisposition.excluded, '退款相关记录暂不自动入账，请核对原消费后手动处理'),
        );
        continue;
      }
      if (RegExp('关闭|失败|撤销|未支付|待支付|已取消|待收款').hasMatch(status)) {
        rows.add(rejected(ImportDisposition.excluded, '未完成交易：$status'));
        continue;
      }
      if (direction != '收入' && direction != '支出') {
        rows.add(rejected(ImportDisposition.excluded, '不计收支或中性交易：$direction'));
        continue;
      }
      if (RegExp('充值|提现|信用卡还款|偿还|理财|基金|余额宝|借贷').hasMatch(kind)) {
        rows.add(rejected(ImportDisposition.excluded, '资产变动不自动记为收支：$kind'));
        continue;
      }
      const completed = {
        '支付成功',
        '交易成功',
        '交易完成',
        '收款成功',
        '已收款',
        '已收钱',
        '已存入零钱',
        '朋友已收钱',
        '转账成功',
        '已到账',
        '已支出',
        '对方已收钱',
      };
      if (!completed.contains(status)) {
        rows.add(rejected(ImportDisposition.invalid, '无法确认交易状态：$status'));
        continue;
      }
      final date = parseTransactionDate(dateText);
      if (date == null) throw const FormatException('交易日期或时间无效');
      final cents = parseMoney(
        field(['金额元', '金额']).replaceAll(RegExp(r'[¥￥,\s]'), ''),
      );
      if (cents == 0) {
        rows.add(rejected(ImportDisposition.excluded, '零金额交易'));
        continue;
      }
      final type = direction == '收入' ? EntryType.income : EntryType.expense;
      var trade = field([
        '交易单号',
        '交易订单号',
        '交易号',
      ]).replaceAll(RegExp(r'[\t\s]'), '');
      if (trade == '/' || trade == '-') trade = '';
      if (trade.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(trade)) {
        throw const FormatException('交易号格式异常，可能被表格软件改写，请使用原始文件');
      }
      final fallback = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                date.toIso8601String(),
                type.name,
                cents,
                counterpart,
                product,
                kind,
              ]),
            ),
          )
          .toString();
      final occurrence = occurrences.update(
        fallback,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      final key = trade.isNotEmpty
          ? '$platform:id:$trade'
          : '$platform:hash:$fallback:$occurrence';
      final duplicate = known.contains(key) || !seen.add(key);
      final suspected = existing.contains(
        '${type.name}|$cents|${date.toIso8601String().substring(0, 16)}',
      );
      rows.add(
        ImportRow(
          line: i + 1,
          description: description,
          reason: duplicate
              ? '该交易已导入或在文件中重复'
              : trade.isEmpty
              ? '缺少交易号，请核对后勾选'
              : suspected
              ? '与已有账单时间、金额相同，请核对后勾选'
              : '可导入',
          disposition: duplicate
              ? ImportDisposition.duplicate
              : trade.isEmpty || suspected
              ? ImportDisposition.review
              : ImportDisposition.ready,
          date: date,
          type: type,
          cents: cents,
          sourceKey: key,
        ),
      );
    } on FormatException catch (error) {
      rows.add(rejected(ImportDisposition.invalid, error.message.toString()));
    }
  }
  if (rows.isEmpty) throw const FormatException('文件中没有交易明细');
  return ImportPreview(platform, fileName, List.unmodifiable(rows));
}

Ledger applyBillImport(
  Ledger ledger,
  ImportPreview preview,
  Set<int> selected,
  String accountId,
  Map<int, String> categories, {
  DateTime? now,
}) {
  final date = now ?? DateTime.now();
  final id = 'import-${date.microsecondsSinceEpoch}';
  final known = {for (final b in ledger.importBatches) ...b.sourceKeys};
  final entries = <LedgerEntry>[];
  for (final row in preview.rows) {
    if (!selected.contains(row.line)) continue;
    if (!row.selectable ||
        row.sourceKey == null ||
        !known.add(row.sourceKey!)) {
      throw const FormatException('选择中包含重复或无效交易，请重新预览');
    }
    entries.add(
      LedgerEntry(
        id: '$id-${row.line}',
        type: row.type!,
        cents: row.cents!,
        date: row.date!,
        category: categories[row.line]!,
        accountId: accountId,
        note: row.description,
        importBatchId: id,
        sourceKey: row.sourceKey,
      ),
    );
  }
  if (entries.isEmpty) throw const FormatException('请至少选择一笔有效交易');
  final batch = ImportBatch(
    id: id,
    platform: preview.platform,
    fileName: preview.fileName,
    createdAt: date,
    fingerprints: {for (final e in entries) e.id: entryFingerprint(e)},
    sourceKeys: [for (final e in entries) e.sourceKey!],
  );
  final next = ledger.copyWith(
    entries: [...ledger.entries, ...entries],
    importBatches: [...ledger.importBatches, batch],
  );
  next.validate();
  return next;
}

Ledger undoBillImport(Ledger ledger, String batchId) {
  if (!ledger.importBatches.any((b) => b.id == batchId)) {
    throw const FormatException('该导入批次已撤销或不存在');
  }
  final next = ledger.copyWith(
    entries: ledger.entries.where((e) => e.importBatchId != batchId).toList(),
    importBatches: ledger.importBatches.where((b) => b.id != batchId).toList(),
  );
  next.validate();
  return next;
}

import 'dart:io';
import 'package:daily_ledger/bill_import.dart';
import 'package:daily_ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('external XLSX with package-absolute relationships and inline strings', () {
    final result = parseBillFile(
      File('test/fixtures/wechat-openpyxl.xlsx').readAsBytesSync(),
      'wx.xlsx',
      Ledger.empty(),
    );
    expect(result.rows.single.cents, 1230);
    expect(result.rows.single.date, DateTime(2026, 11, 8, 12, 30));
    expect(result.rows.single.description, contains('测试店铺'));
    expect(result.rows.single.sourceKey, '微信:id:v030-xlsx-wx');
  });
}

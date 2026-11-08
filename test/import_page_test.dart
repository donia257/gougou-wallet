import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_ledger/import_page.dart';
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'bill_import_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    for (final font in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'DailySans': 'assets/fonts/Manrope.ttf',
      'DailyChinese': 'assets/fonts/NotoSansSC-bundled.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets(
    'preview requires confirmation, changes category, persists exact selection',
    (tester) async {
      var ledger = Ledger.empty();
      var commits = 0;
      final preview = fixtures.wx(
        '${fixtures.wechatRow}\n'
        '${fixtures.wechatRow.replaceFirst('支付成功', '已全额退款')}',
      );
      await tester.pumpWidget(
        DailyApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => BillImportPreviewPage(
                      preview: preview,
                      currentLedger: () => ledger,
                      onCommit: (next, reason) async {
                        commits++;
                        ledger = next;
                        return true;
                      },
                    ),
                  ),
                ),
                child: const Text('打开预览'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开预览'));
      await tester.pumpAndSettle();
      expect(find.text('确认导入 1 笔'), findsOneWidget);
      expect(ledger.entries, isEmpty);
      await tester.ensureVisible(find.text('批量支出分类'));
      await tester.tap(find.text('批量支出分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('餐饮'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认导入 1 笔'));
      await tester.pumpAndSettle();
      expect(find.text('确认导入 1 笔？'), findsOneWidget);
      expect(commits, 0);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(ledger.entries.single.cents, 1230);
      expect(ledger.entries.single.category, 'expense-0');
      expect(find.text('打开预览'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'batch undo cancellation and confirmation preserve later manual records',
    (tester) async {
      var ledger = fixtures.apply(
        Ledger.empty(),
        fixtures.wx(fixtures.wechatRow),
      );
      final imported = ledger.entries.single;
      ledger = ledger.copyWith(
        entries: [
          ...ledger.entries,
          LedgerEntry(
            id: 'manual',
            type: EntryType.expense,
            cents: 50,
            date: imported.date,
            category: imported.category,
            accountId: 'cash',
          ),
        ],
      );
      var commits = 0;
      await tester.pumpWidget(
        DailyApp(
          home: BillImportPage(
            currentLedger: () => ledger,
            onCommit: (next, reason) async {
              commits++;
              ledger = next;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('撤销本次导入'));
      await tester.tap(find.text('撤销本次导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(commits, 0);
      await tester.tap(find.text('撤销本次导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(ledger.entries.single.id, 'manual');
      expect(ledger.importBatches, isEmpty);
      expect(find.text('还没有导入记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 720), const Size(768, 1024)]) {
    testWidgets('import preview fits $size at large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ledger = Ledger.empty();
      final preview = fixtures.wx(
        '${fixtures.wechatRow}\n'
        '${fixtures.wechatRow.replaceFirst('支付成功', '已全额退款')}',
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        DailyApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(1.4),
            ),
            child: RepaintBoundary(
              key: boundaryKey,
              child: BillImportPreviewPage(
                preview: preview,
                currentLedger: () => ledger,
                onCommit: (_, _) async => false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/import-preview-${size.width.toInt()}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.textContaining('退款相关记录暂不自动入账'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

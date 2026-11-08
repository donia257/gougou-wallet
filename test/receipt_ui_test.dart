import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_ledger/entry_editor.dart';
import 'package:daily_ledger/main.dart';
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/ocr_service.dart';
import 'package:daily_ledger/receipt_parser.dart';
import 'package:daily_ledger/receipt_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'receipt_parser_test.dart' as fixtures;

class FakeOcr extends OcrService {
  FakeOcr(this.document);
  final OcrDocument? document;
  @override
  Future<OcrDocument?> pickAndRecognize() async => document;
}

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

  testWidgets('OCR review fills editor but saves only after explicit save', (
    tester,
  ) async {
    LedgerEntry? saved;
    final ledger = Ledger.empty();
    await tester.pumpWidget(
      DailyApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EntryEditor(
                    ledger: ledger,
                    ocrService: FakeOcr(fixtures.receipt(fixtures.paymentText)),
                    onSave: (e) async {
                      saved = e;
                      return true;
                    },
                  ),
                ),
              ),
              child: const Text('新建'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图片识别'));
    await tester.pumpAndSettle();
    expect(find.text('核对图片账单'), findsOneWidget);
    expect(saved, isNull);
    await tester.tap(find.text('填入记账页'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    final amount = tester.widget<TextFormField>(
      find.byKey(const ValueKey('entry-amount')),
    );
    expect(amount.controller!.text, '28.50');
    await tester.ensureVisible(find.text('保存这一笔'));
    await tester.tap(find.text('保存这一笔'));
    await tester.pumpAndSettle();
    expect(saved!.cents, 2850);
    expect(saved!.category, 'expense-0');
    expect(saved!.note, '星巴克咖啡');
    expect(saved!.date, DateTime(2026, 11, 8, 12, 30));
    expect(saved!.accountId, 'cash');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelled image selection leaves the existing amount unchanged',
    (tester) async {
      await tester.pumpWidget(
        DailyApp(
          home: EntryEditor(
            ledger: Ledger.empty(),
            ocrService: FakeOcr(null),
            onSave: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-amount')),
        '99.90',
      );
      await tester.tap(find.byTooltip('图片识别'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('entry-amount')))
            .controller!
            .text,
        '99.90',
      );
      expect(find.text('核对图片账单'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 720), const Size(768, 1024)]) {
    testWidgets(
      'OCR review fits $size with large text and exposes source text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final doc = fixtures.receipt(fixtures.paymentText);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          DailyApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(1.4),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: ReceiptReviewPage(
                  document: doc,
                  ledger: Ledger.empty(),
                  suggestion: parseReceipt(doc, Ledger.empty()),
                  currentDate: DateTime(2026, 11, 8),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/ocr-review-${size.width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('查看识别原文'));
        await tester.tap(find.text('查看识别原文'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'refund screenshot cannot be applied as an ordinary transaction',
    (tester) async {
      final doc = fixtures.receipt('退款成功\n￥20.00');
      await tester.pumpWidget(
        DailyApp(
          home: ReceiptReviewPage(
            document: doc,
            ledger: Ledger.empty(),
            suggestion: parseReceipt(doc, Ledger.empty()),
            currentDate: DateTime(2026, 11, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '填入记账页'))
            .onPressed,
        isNull,
      );
    },
  );
}

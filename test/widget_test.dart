import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/main.dart';
import 'package:daily_ledger/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryRepository extends LedgerRepository {
  Ledger data = Ledger.empty();
  @override
  Future<Ledger> open() async => data;
  @override
  Future<void> save(Ledger ledger) async {
    data = ledger;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'DailySans',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'DailyChinese',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-bundled.ttf'))).load();
  });
  testWidgets('home, entry save, filters and accounts work on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryRepository();
    await tester.pumpWidget(DailyApp(home: LedgerHome(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('从今天的第一笔开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '12.30');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃这次修改？'), findsOneWidget);
    await tester.tap(find.text('继续记账'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存这一笔'));
    await tester.tap(find.text('保存这一笔'));
    await tester.pumpAndSettle();
    expect(repository.data.entries.single.cents, 1230);
    expect(repository.data.balance('cash'), -1230);
    expect(find.text('记下这一笔'), findsNothing);
    await tester.tap(find.text('账单'));
    await tester.pumpAndSettle();
    expect(find.text('共 1 笔'), findsOneWidget);
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(find.text('钱花在了哪里'), findsOneWidget);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('我的账户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home layout at narrow width and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      DailyApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(1.4),
          ),
          child: RepaintBoundary(
            key: boundaryKey,
            child: LedgerHome(repository: MemoryRepository()),
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
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/home-preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/main.dart';
import 'package:daily_ledger/repository.dart';
import 'package:daily_ledger/category_page.dart';
import 'package:daily_ledger/update_page.dart';
import 'package:daily_ledger/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryRepository extends LedgerRepository {
  MemoryRepository([Ledger? initial]) {
    if (initial != null) data = initial;
  }
  Ledger data = Ledger.empty();
  @override
  Future<Ledger> open() async => data;
  @override
  Future<void> save(Ledger ledger, {String? snapshotReason}) async {
    data = ledger;
  }

  @override
  Future<List<RecoverySnapshot>> snapshots() async => [];
}

class FakeUpdateService extends UpdateService {
  int calls = 0;
  @override
  Future<GithubRelease> latest() async {
    calls++;
    return const GithubRelease(tag: 'v0.3.0', notes: '更新内容');
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
  testWidgets('home, entry save, filters and settings work on a small phone', (
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
    expect(find.text('放弃这次修改？'), findsNothing);
    expect(find.text('记下这一笔'), findsNothing);
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('entry-amount')), '12.30');
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
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('我的账户'), findsNothing);
    expect(find.text('分类管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'time selection, save and continue, copy and direct back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemoryRepository();
      await tester.pumpWidget(
        DailyApp(home: LedgerHome(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('记一笔'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-amount')),
        '11.22',
      );
      await tester.ensureVisible(find.text('时间'));
      await tester.tap(find.text('时间'));
      await tester.pumpAndSettle();
      final timeFields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(timeFields.first, '08');
      await tester.enterText(timeFields.last, '45');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('08:45'), findsOneWidget);
      await tester.ensureVisible(find.text('保存并继续'));
      await tester.tap(find.text('保存并继续'));
      await tester.pumpAndSettle();
      expect(repository.data.entries.single.date.hour, 8);
      expect(repository.data.entries.single.date.minute, 45);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('entry-amount')))
            .controller!
            .text,
        isEmpty,
      );
      for (final amount in ['20.00', '30.00']) {
        await tester.ensureVisible(find.byKey(const ValueKey('entry-amount')));
        await tester.enterText(
          find.byKey(const ValueKey('entry-amount')),
          amount,
        );
        await tester.ensureVisible(find.text('保存并继续'));
        await tester.tap(find.text('保存并继续'));
        await tester.pumpAndSettle();
      }
      expect(repository.data.entries.length, 3);
      expect(repository.data.entries.map((e) => e.id).toSet().length, 3);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('放弃这次修改？'), findsNothing);
      await tester.tap(find.text('账单'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(ValueKey('entry-${repository.data.entries.first.id}')),
      );
      await tester.tap(
        find.byKey(ValueKey('entry-${repository.data.entries.first.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(find.text('复制记一笔'), findsOneWidget);
      await tester.ensureVisible(find.text('保存这一笔'));
      await tester.tap(find.text('保存这一笔'));
      await tester.pumpAndSettle();
      expect(repository.data.entries.length, 4);
      expect(
        repository.data.entries.last.id,
        isNot(repository.data.entries.first.id),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category add, rename, reorder and delete migrate historical entries',
    (tester) async {
      var ledger = Ledger.empty();
      ledger = ledger.copyWith(
        categories: [
          ledger.categories[0],
          ledger.categories[1],
          ledger.categoriesFor(EntryType.income).first,
        ],
        entries: [
          LedgerEntry(
            id: 'old',
            type: EntryType.expense,
            cents: 100,
            date: DateTime.now(),
            category: 'expense-0',
            accountId: 'cash',
          ),
        ],
      );
      await tester.pumpWidget(
        DailyApp(
          home: CategoryPage(
            ledger: ledger,
            onSave: (next) async {
              ledger = next;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加分类'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '宠物');
      await tester.tap(find.text('保存分类'));
      await tester.pumpAndSettle();
      expect(ledger.categoriesFor(EntryType.expense).length, 3);
      await tester.tap(find.text('餐饮'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '三餐');
      await tester.tap(find.text('保存分类'));
      await tester.pumpAndSettle();
      expect(ledger.categoryName(ledger.entries.single), '三餐');
      await tester.tap(find.byTooltip('分类操作').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('上移'));
      await tester.pumpAndSettle();
      expect(ledger.categoriesFor(EntryType.expense)[1].name, '宠物');
      await tester.tap(find.byTooltip('分类操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('此分类有 1 笔账单，请选择迁入分类。'), findsOneWidget);
      await tester.tap(find.text('删除分类'));
      await tester.pumpAndSettle();
      expect(ledger.categoryName(ledger.entries.single), '宠物');
      expect(ledger.entries.single.cents, 100);
      expect(ledger.balance('cash'), -100);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual update checking waits for the user and shows a newer stable release',
    (tester) async {
      final service = FakeUpdateService();
      await tester.pumpWidget(DailyApp(home: UpdatePage(service: service)));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await tester.tap(find.widgetWithText(FilledButton, '检查更新'));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(find.text('发现新版本 v0.3.0'), findsOneWidget);
      expect(find.text('到 GitHub 下载新版'), findsOneWidget);
    },
  );

  testWidgets(
    'daily and bills use day sections and stay lazy for a large ledger',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final entries = List.generate(
        10000,
        (index) => LedgerEntry(
          id: 'large-$index',
          type: EntryType.expense,
          cents: 100,
          date: DateTime(
            now.year,
            now.month,
            1 + index % 28,
            index % 24,
            index % 60,
          ),
          category: 'expense-0',
          accountId: 'cash',
        ),
      );
      final repository = MemoryRepository(
        Ledger.empty().copyWith(entries: entries),
      );
      await tester.pumpWidget(
        DailyApp(home: LedgerHome(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('最近的生活'), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
      await tester.tap(find.text('账单'));
      await tester.pumpAndSettle();
      expect(find.text('共 10000 笔'), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
      expect(
        find.byKey(
          ValueKey(
            'day-${now.year}-${now.month.toString().padLeft(2, '0')}-28',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

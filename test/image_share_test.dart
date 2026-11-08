import 'dart:async';
import 'package:daily_ledger/main.dart';
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/entry_editor.dart';
import 'package:daily_ledger/image_share_service.dart';
import 'package:daily_ledger/ocr_service.dart';
import 'package:daily_ledger/receipt_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' as widgets;
import 'receipt_parser_test.dart' as fixtures;

class PendingShares extends ImageShareService {
  final pending = <SharedReceiptImage>[];
  final released = <String>[];
  final returned = <String>[];
  void Function()? notify;
  int takes = 0;
  @override
  void start(void Function() onAvailable) {
    notify = onAvailable;
    onAvailable();
  }

  void add(String id, {String? error}) {
    pending.add(
      SharedReceiptImage(
        id: id,
        path: error == null ? '/share/$id.png' : null,
        error: error,
      ),
    );
    notify?.call();
  }

  @override
  Future<SharedReceiptImage?> takeNext() async {
    takes++;
    return pending.isEmpty ? null : pending.removeAt(0);
  }

  @override
  Future<void> release(SharedReceiptImage image) async {
    released.add(image.id);
  }

  @override
  Future<void> putBack(SharedReceiptImage image) async {
    returned.add(image.id);
    pending.insert(0, image);
  }

  @override
  void dispose() {
    notify = null;
  }
}

class SharedOcr extends OcrService {
  final paths = <String>[];
  @override
  Future<OcrDocument> recognizeImage(String path) async {
    paths.add(path);
    if (path.contains('unreadable')) throw const FormatException('未识别到文字');
    return fixtures.receipt(fixtures.paymentText);
  }

  @override
  Future<OcrDocument?> pickAndRecognize() async =>
      throw StateError('Sharing must bypass the album picker');
}

class DelayedLedger extends widgets.MemoryRepository {
  final ready = Completer<Ledger>();
  @override
  Future<Ledger> open() => ready.future;
}

class AndroidShares extends ImageShareService {
  @override
  bool get isSupported => true;
}

class SlowSharedOcr extends SharedOcr {
  final firstResult = Completer<OcrDocument>();
  @override
  Future<OcrDocument> recognizeImage(String path) {
    if (path.contains('slow')) {
      paths.add(path);
      return firstResult.future;
    }
    return super.recognizeImage(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    'cancelled in-flight OCR finishes before starting the next queued share',
    (tester) async {
      final repository = widgets.MemoryRepository();
      final shares = PendingShares()
        ..add('slow')
        ..add('next');
      final ocr = SlowSharedOcr();
      await tester.pumpWidget(
        DailyApp(
          home: LedgerHome(
            repository: repository,
            imageShares: shares,
            ocrService: ocr,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(ocr.paths, ['/share/slow.png']);
      await tester.binding.handlePopRoute();
      await tester.pump();
      // Deliver OCR before the old route's exit animation has disposed its State.
      expect(ocr.paths, ['/share/slow.png']);
      ocr.firstResult.complete(fixtures.receipt(fixtures.paymentText));
      await tester.pumpAndSettle();
      expect(ocr.paths, ['/share/slow.png', '/share/next.png']);
      expect(find.text('核对图片账单'), findsOneWidget);
      expect(repository.data.entries, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shares.released, ['slow', 'next']);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'share bridge pulls, returns and acknowledges an image by opaque ID',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(ImageShareService.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'takePendingShare') {
          return {'id': 'abc', 'path': '/cache/abc.image', 'error': null};
        }
        return null;
      });
      final service = AndroidShares();
      addTearDown(() {
        service.dispose();
        messenger.setMockMethodCallHandler(ImageShareService.channel, null);
      });
      var notifications = 0;
      service.start(() => notifications++);
      expect(notifications, 1);
      final image = (await service.takeNext())!;
      expect(image.id, 'abc');
      expect(image.path, '/cache/abc.image');
      await service.putBack(image);
      await service.release(image);
      expect(calls.map((c) => c.method), [
        'takePendingShare',
        'returnShare',
        'releaseShare',
      ]);
      expect(calls.last.arguments, {'id': 'abc'});
    },
  );

  testWidgets(
    'cold sharing waits for ledger readiness, bypasses picker and saves only on request',
    (tester) async {
      final repository = DelayedLedger();
      final shares = PendingShares()..add('cold');
      final ocr = SharedOcr();
      await tester.pumpWidget(
        DailyApp(
          home: LedgerHome(
            repository: repository,
            imageShares: shares,
            ocrService: ocr,
          ),
        ),
      );
      await tester.pump();
      expect(shares.takes, 0);
      expect(ocr.paths, isEmpty);
      repository.ready.complete(Ledger.empty());
      await tester.pumpAndSettle();
      expect(find.text('核对图片账单'), findsOneWidget);
      expect(ocr.paths, ['/share/cold.png']);
      expect(repository.data.entries, isEmpty);
      await tester.tap(find.text('填入记账页'));
      await tester.pumpAndSettle();
      expect(repository.data.entries, isEmpty);
      await tester.tap(find.text('保存这一笔'));
      await tester.pumpAndSettle();
      expect(repository.data.entries.single.cents, 2850);
      expect(shares.released, ['cold']);
      expect(ocr.paths.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'warm sharing preserves an unfinished manual entry until it is saved',
    (tester) async {
      final repository = widgets.MemoryRepository();
      final shares = PendingShares();
      final ocr = SharedOcr();
      await tester.pumpWidget(
        DailyApp(
          home: LedgerHome(
            repository: repository,
            imageShares: shares,
            ocrService: ocr,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('记一笔'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-amount')),
        '99.90',
      );
      shares.add('warm');
      shares.notify?.call();
      await tester.pumpAndSettle();
      expect(find.text('核对图片账单'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('entry-amount')))
            .controller!
            .text,
        '99.90',
      );
      expect(ocr.paths, isEmpty);
      await tester.tap(find.text('保存这一笔'));
      await tester.pumpAndSettle();
      expect(repository.data.entries.single.cents, 9990);
      expect(find.text('核对图片账单'), findsOneWidget);
      expect(ocr.paths, ['/share/warm.png']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shares.released, ['warm']);
      expect(repository.data.entries.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two shared images are processed once each in order and cancelled without writes',
    (tester) async {
      final repository = widgets.MemoryRepository();
      final shares = PendingShares()
        ..add('one')
        ..add('two');
      final ocr = SharedOcr();
      await tester.pumpWidget(
        DailyApp(
          home: LedgerHome(
            repository: repository,
            imageShares: shares,
            ocrService: ocr,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ocr.paths, ['/share/one.png']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(ocr.paths, ['/share/one.png', '/share/two.png']);
      expect(shares.released, ['one']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shares.released, ['one', 'two']);
      expect(repository.data.entries, isEmpty);
      expect(find.byType(EntryEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired URI reports an error without opening an editor or changing ledger',
    (tester) async {
      final repository = widgets.MemoryRepository();
      final shares = PendingShares()..add('denied', error: '分享图片授权已失效');
      final ocr = SharedOcr();
      await tester.pumpWidget(
        DailyApp(
          home: LedgerHome(
            repository: repository,
            imageShares: shares,
            ocrService: ocr,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('分享图片授权已失效'), findsOneWidget);
      expect(shares.released, ['denied']);
      expect(ocr.paths, isEmpty);
      expect(repository.data.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unreadable shared image can return to home and releases its temporary copy',
    (tester) async {
      final repository = widgets.MemoryRepository();
      final shares = PendingShares()..add('unreadable');
      final ocr = SharedOcr();
      await tester.pumpWidget(
        DailyApp(
          home: LedgerHome(
            repository: repository,
            imageShares: shares,
            ocrService: ocr,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未识别到文字'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shares.released, ['unreadable']);
      expect(repository.data.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

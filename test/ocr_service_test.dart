import 'package:daily_ledger/ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(OcrService.channel, null));

  test(
    'native OCR channel transports local path and positioned Chinese lines',
    () async {
      messenger.setMockMethodCallHandler(OcrService.channel, (call) async {
        expect(call.method, 'recognizeImage');
        expect(call.arguments, {'path': '/local/receipt.png'});
        return {
          'text': '支付成功\n￥12.30',
          'lines': [
            {
              'text': '￥12.30',
              'left': 10,
              'top': 20,
              'right': 80,
              'bottom': 40,
            },
          ],
        };
      });
      final result = await OcrService().recognizeImage('/local/receipt.png');
      expect(result.text, contains('支付成功'));
      expect(result.lines.single.left, 10);
      expect(result.lines.single.height, 20);
    },
  );

  test('empty results and native image failures stay actionable', () async {
    messenger.setMockMethodCallHandler(
      OcrService.channel,
      (_) async => {'text': '', 'lines': []},
    );
    await expectLater(
      OcrService().recognizeImage('empty.png'),
      throwsFormatException,
    );
    messenger.setMockMethodCallHandler(
      OcrService.channel,
      (_) async =>
          throw PlatformException(code: 'image_invalid', message: '无法读取图片'),
    );
    await expectLater(
      OcrService().recognizeImage('bad.png'),
      throwsA(isA<PlatformException>()),
    );
  });
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'import_files.dart';
import 'receipt_parser.dart';

class OcrService {
  static const channel = MethodChannel('wangwang_wallet/chinese_ocr');

  Future<OcrDocument?> pickAndRecognize() async {
    final selection = await FilePicker.platform.pickFiles(type: FileType.image);
    if (selection == null) return null;
    final file = selection.files.single;
    if (file.size > maxImportBytes) throw const FormatException('图片不能超过 20 MB');
    if (file.path != null) return recognizeImage(file.path!);
    final bytes = await readImportFile(file);
    final directory = await Directory.systemTemp.createTemp('wallet-ocr-');
    try {
      final image = File('${directory.path}/image');
      await image.writeAsBytes(bytes, flush: true);
      return await recognizeImage(image.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<OcrDocument> recognizeImage(String path) async {
    final response = await channel.invokeMapMethod<Object?, Object?>(
      'recognizeImage',
      {'path': path},
    );
    if (response == null) throw const FormatException('没有收到识别结果，请重试');
    final document = OcrDocument.fromMap(response);
    if (document.text.trim().isEmpty &&
        document.lines.every((l) => l.text.trim().isEmpty)) {
      throw const FormatException('未识别到文字，请选择清晰的支付截图或小票');
    }
    return document;
  }
}

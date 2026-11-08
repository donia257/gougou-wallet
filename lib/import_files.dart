import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

const maxImportBytes = 20 * 1024 * 1024;

/// Shared by backups, payment exports, and image recognition.
Future<Uint8List> readImportFile(PlatformFile file) async {
  if (file.size > maxImportBytes) throw const FormatException('文件不能超过 20 MB');
  final bytes = file.bytes ?? await File(file.path!).readAsBytes();
  if (bytes.isEmpty || bytes.length > maxImportBytes) {
    throw const FormatException('请选择非空且不超过 20 MB 的文件');
  }
  return bytes;
}

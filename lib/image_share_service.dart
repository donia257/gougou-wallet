import 'dart:io';
import 'package:flutter/services.dart';

class SharedReceiptImage {
  const SharedReceiptImage({required this.id, this.path, this.error});
  final String id;
  final String? path, error;
}

/// A pull/ack handoff keeps cold-start events and defers shares during editing.
class ImageShareService {
  static const channel = MethodChannel('wangwang_wallet/image_share');
  bool _started = false;
  bool get isSupported => Platform.isAndroid;

  void start(void Function() onAvailable) {
    if (!isSupported) return;
    _started = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pendingShareAvailable') onAvailable();
    });
    onAvailable();
  }

  Future<SharedReceiptImage?> takeNext() async {
    if (!_started) return null;
    final data = await channel.invokeMapMethod<String, dynamic>(
      'takePendingShare',
    );
    if (data == null) return null;
    return SharedReceiptImage(
      id: data['id'] as String,
      path: data['path'] as String?,
      error: data['error'] as String?,
    );
  }

  Future<void> release(SharedReceiptImage image) async {
    if (_started) {
      await channel.invokeMethod<void>('releaseShare', {'id': image.id});
    }
  }

  Future<void> putBack(SharedReceiptImage image) async {
    if (_started) {
      await channel.invokeMethod<void>('returnShare', {'id': image.id});
    }
  }

  void dispose() {
    if (_started) channel.setMethodCallHandler(null);
    _started = false;
  }
}

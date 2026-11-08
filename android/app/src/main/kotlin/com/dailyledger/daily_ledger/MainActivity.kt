package com.dailyledger.daily_ledger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ocr: ChineseOcrHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ocr = ChineseOcrHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wangwang_wallet/chinese_ocr")
            .setMethodCallHandler(ocr)
    }

    override fun onDestroy() {
        ocr?.close()
        ocr = null
        super.onDestroy()
    }
}

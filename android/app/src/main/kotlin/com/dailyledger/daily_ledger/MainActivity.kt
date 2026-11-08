package com.dailyledger.daily_ledger

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ocr: ChineseOcrHandler? = null
    private var shares: ImageShareHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ocr = ChineseOcrHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wangwang_wallet/chinese_ocr")
            .setMethodCallHandler(ocr)
        shares = ImageShareHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        shares?.receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shares?.receive(intent)
    }

    override fun onDestroy() {
        ocr?.close()
        ocr = null
        shares?.close()
        shares = null
        super.onDestroy()
    }
}

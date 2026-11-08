package com.dailyledger.daily_ledger

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Owns the recognizer lifecycle. Decode/rotation runs off the UI thread. */
class ChineseOcrHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val recognizerDelegate = lazy { TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()) }
    private val recognizer by recognizerDelegate
    private var pending: MethodChannel.Result? = null
    @Volatile private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognizeImage") { result.notImplemented(); return }
        if (closed || pending != null) {
            result.error("busy", "正在识别，请稍候", null); return
        }
        val path = call.argument<String>("path")
        val file = path?.let { File(it) }
        if (file == null || !file.isFile || file.length() !in 1..20L * 1024 * 1024) {
            result.error("image_invalid", "请选择不超过 20 MB 的有效图片", null); return
        }
        pending = result
        executor.execute {
            try {
                val bitmap = decodeImage(file.path)
                activity.runOnUiThread {
                    if (closed) { bitmap.recycle(); return@runOnUiThread }
                    try {
                      recognizer.process(InputImage.fromBitmap(bitmap, 0))
                        .addOnSuccessListener { text ->
                            val lines = text.textBlocks.flatMap { it.lines }.map { line ->
                                val box = line.boundingBox
                                mapOf("text" to line.text, "left" to (box?.left ?: 0),
                                    "top" to (box?.top ?: 0), "right" to (box?.right ?: 0),
                                    "bottom" to (box?.bottom ?: 0))
                            }
                            val response = mapOf("text" to text.text, "lines" to lines)
                            val reply = pending; pending = null
                            reply?.success(response)
                        }
                        .addOnFailureListener { fail("recognition_failed", "本地识别失败，请换一张清晰图片重试") }
                        .addOnCompleteListener { bitmap.recycle() }
                    } catch (_: Exception) {
                        bitmap.recycle()
                        fail("recognition_failed", "本地识别暂时不可用，请重试或更换图片")
                    }
                }
            } catch (_: OutOfMemoryError) {
                activity.runOnUiThread { fail("image_large", "图片过大，请裁剪后重试") }
            } catch (_: Exception) {
                activity.runOnUiThread { fail("image_invalid", "无法读取图片，请选择 JPG、PNG 或系统支持的图片") }
            }
        }
    }

    private fun fail(code: String, message: String) {
        val reply = pending; pending = null
        reply?.error(code, message, null)
    }

    private fun decodeImage(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2560) sample *= 2
        val bitmap = requireNotNull(BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888
        }))
        val orientation = try {
            ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(270f)
        }
        if (matrix.isIdentity) return bitmap
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    fun close() {
        closed = true
        fail("cancelled", "图片识别已取消")
        if (recognizerDelegate.isInitialized()) recognizer.close()
        executor.shutdownNow()
    }
}

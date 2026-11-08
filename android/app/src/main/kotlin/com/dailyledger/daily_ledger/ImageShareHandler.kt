package com.dailyledger.daily_ledger

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors

/** Copies temporary content URI grants before handing the image to Flutter. */
class ImageShareHandler(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private data class Receipt(val id: String, val file: File?, val error: String?) {
        fun asMap() = mapOf("id" to id, "path" to file?.path, "error" to error)
    }

    private val channel = MethodChannel(messenger, "wangwang_wallet/image_share")
    private val executor = Executors.newSingleThreadExecutor()
    private val queue = ArrayDeque<Receipt>()
    private val leased = mutableMapOf<String, Receipt>()
    private val directory = File(activity.cacheDir, "shared_receipts")
    private var copying = 0
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler(this)
        executor.execute {
            // Only clean this handler's own old private cache, never the source image.
            val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
            directory.listFiles()?.filter { it.name.startsWith("receipt-") && it.lastModified() < cutoff }
                ?.forEach { it.delete() }
        }
    }

    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || closed) return
        if (intent.getBooleanExtra("wallet_share_received", false)) return
        intent.putExtra("wallet_share_received", true)
        if (queue.size + leased.size + copying >= 5) {
            Toast.makeText(activity, "待处理图片较多，请先完成当前记账", Toast.LENGTH_LONG).show()
            return
        }
        val uri = streamUri(intent)
        val mime = intent.type.orEmpty()
        if (!mime.startsWith("image/") || uri?.scheme != "content") {
            enqueue(Receipt(UUID.randomUUID().toString(), null, "分享内容不是可读取的单张图片，请从相册重新分享"))
            return
        }
        copying++
        executor.execute {
            val receipt = copyImage(uri)
            activity.runOnUiThread {
                copying--
                if (closed) receipt.file?.delete() else enqueue(receipt)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? = try {
        val extra = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        extra ?: intent.clipData?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.uri ?: intent.data
    } catch (_: RuntimeException) { null }

    private fun copyImage(uri: Uri): Receipt {
        val id = UUID.randomUUID().toString()
        var file: File? = null
        return try {
            check(directory.isDirectory || directory.mkdirs())
            val destination = File.createTempFile("receipt-", ".image", directory)
            file = destination
            activity.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input)
                destination.outputStream().use { output ->
                    val buffer = ByteArray(32 * 1024)
                    var size = 0L
                    while (true) {
                        if (closed || Thread.currentThread().isInterrupted) throw InterruptedException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        size += count
                        if (size > 20L * 1024 * 1024) throw ImageTooLarge()
                        output.write(buffer, 0, count)
                    }
                    require(size > 0)
                }
            }
            Receipt(id, file, null)
        } catch (_: ImageTooLarge) {
            file?.delete()
            Receipt(id, null, "分享图片不能超过 20 MB，请裁剪后重新分享")
        } catch (_: Exception) {
            file?.delete()
            Receipt(id, null, "无法读取分享图片，可能授权已失效，请从相册重新分享")
        }
    }

    private class ImageTooLarge : Exception()

    private fun enqueue(receipt: Receipt) {
        queue.addLast(receipt)
        Toast.makeText(activity, "图片已接收", Toast.LENGTH_SHORT).show()
        channel.invokeMethod("pendingShareAvailable", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingShare" -> {
                val receipt = queue.pollFirst()
                if (receipt != null) leased[receipt.id] = receipt
                result.success(receipt?.asMap())
            }
            "releaseShare" -> {
                leased.remove(call.argument<String>("id"))?.file?.delete()
                result.success(null)
            }
            "returnShare" -> {
                leased.remove(call.argument<String>("id"))?.let { queue.addFirst(it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        queue.forEach { it.file?.delete() }
        leased.values.forEach { it.file?.delete() }
        queue.clear()
        leased.clear()
    }
}

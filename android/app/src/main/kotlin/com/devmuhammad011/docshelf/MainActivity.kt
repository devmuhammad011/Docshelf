package com.devmuhammad011.docshelf

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val pending = ArrayDeque<Map<String, Any>>()
    private val importer = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "docshelf/documents")
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "takeDocument") {
                result.success(pending.removeFirstOrNull())
            } else {
                result.notImplemented()
            }
        }
        receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    private fun receive(intent: Intent?) {
        intent ?: return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            else -> null
        } ?: return
        if (uri.scheme != "content") return
        val mime = intent.type
        importer.execute {
            val document = try {
                importDocument(uri, mime)
            } catch (error: Exception) {
                mapOf("error" to (if (error is IOException) {
                    "Couldn’t import this file. Check that it is available and under 100 MB."
                } else {
                    "Couldn’t import this file. Choose a supported document."
                }))
            }
            runOnUiThread {
                if (isDestroyed) {
                    (document["path"] as? String)?.let { File(it).delete() }
                } else {
                    pending.addLast(document)
                    channel?.invokeMethod("documentAvailable", null)
                }
            }
        }
    }

    private fun importDocument(uri: Uri, mime: String?): Map<String, Any> {
        val extensions = mapOf(
            "application/pdf" to "pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" to "docx",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" to "xlsx",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" to "pptx",
            "text/plain" to "txt",
            "text/csv" to "csv"
        )
        val nameFromProvider = contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
        )?.use { if (it.moveToFirst()) it.getString(0) else null }
        val base = nameFromProvider?.substringAfterLast('/')?.substringAfterLast('\\')
            ?.takeIf { it.isNotBlank() && it != "." && it != ".." } ?: "Document"
        val extension = base.substringAfterLast('.', "").lowercase()
        val name = when {
            extension in extensions.values -> base
            extension.isEmpty() && mime in extensions -> "$base.${extensions[mime]}"
            else -> throw IllegalArgumentException("Unsupported document")
        }
        val target = File.createTempFile("docshelf-", ".incoming", cacheDir)
        try {
            var total = 0L
            val input = contentResolver.openInputStream(uri) ?: throw IOException()
            input.use { source ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > 100L * 1024 * 1024) throw IOException("File too large")
                        output.write(buffer, 0, count)
                    }
                }
            }
            return mapOf("name" to name, "path" to target.path, "size" to total)
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        importer.shutdown()
        for (document in pending) {
            (document["path"] as? String)?.let { File(it).delete() }
        }
        pending.clear()
        super.onDestroy()
    }
}

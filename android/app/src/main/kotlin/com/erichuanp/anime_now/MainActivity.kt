package com.erichuanp.anime_now

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anime_now/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
                    )
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name") ?: "backup.json"
                        val content = call.argument<String>("content") ?: ""
                        try {
                            result.success(saveToDownloads(name, content))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Writes Download/AnimeNow/<name>; replaces an existing file of the same name. */
    private fun saveToDownloads(name: String, content: String): String {
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/AnimeNow"
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            // Remove a previous copy so we don't end up with "anime (1).json".
            resolver.delete(
                collection,
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                arrayOf("$relative/", name)
            )
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            }
            val uri = resolver.insert(collection, values) ?: throw IllegalStateException("MediaStore insert failed")
            resolver.openOutputStream(uri)?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                ?: throw IllegalStateException("cannot open $uri")
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "AnimeNow")
            dir.mkdirs()
            File(dir, name).writeText(content, Charsets.UTF_8)
        }
        return "$relative/$name"
    }
}

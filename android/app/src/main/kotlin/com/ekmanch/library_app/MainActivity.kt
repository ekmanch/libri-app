package com.ekmanch.library_app

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The image on the clipboard, for Add / edit entry › Pick a cover:
        // upload from (Paste image). Flutter's own clipboard is text only.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "libri/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasImage" -> result.success(clipboardImage() != null)
                    "readImage" -> {
                        val uri = clipboardImage()
                        if (uri == null) {
                            result.success(null)
                        } else {
                            Thread {
                                val bytes = try {
                                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                                } catch (e: Exception) {
                                    null
                                }
                                runOnUiThread { result.success(bytes) }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// The first image the clipboard holds, when it holds one.
    private fun clipboardImage(): Uri? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val description = clipboard.primaryClipDescription ?: return null
        if (!description.hasMimeType("image/*")) return null
        val clip = try {
            clipboard.primaryClip
        } catch (e: SecurityException) {
            null
        } ?: return null
        for (i in 0 until clip.itemCount) {
            val uri = clip.getItemAt(i).uri ?: continue
            return uri
        }
        return null
    }
}

package com.vtrack.vtrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val exportChannel = "vtrack/export"
    private val exportNotificationChannelId = "export_downloads"
    private val generalNotificationChannelId = "vtrack_general"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        createNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidSdkInt" -> {
                        result.success(Build.VERSION.SDK_INT)
                    }
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "vtrack_image"
                        val mimeType = call.argument<String>("mimeType") ?: "image/png"

                        if (bytes == null || bytes.isEmpty()) {
                            result.error("invalid_bytes", "Data gambar kosong", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val savedPath = saveImage(bytes, name, mimeType)
                            result.success(
                                mapOf(
                                    "isSuccess" to true,
                                    "path" to savedPath
                                )
                            )
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                    "notifyExportReady" -> {
                        val path = call.argument<String>("path")
                        val title = call.argument<String>("title") ?: "File siap dibuka"
                        val mimeType = call.argument<String>("mimeType")
                            ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

                        if (path.isNullOrEmpty()) {
                            result.error("invalid_path", "Path file kosong", null)
                            return@setMethodCallHandler
                        }

                        showExportNotification(path, title, mimeType)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveImage(bytes: ByteArray, name: String, mimeType: String): String {
        val fileName = if (name.endsWith(".png", ignoreCase = true)) name else "$name.png"

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/VTrack"
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Gagal membuat file gambar")

            resolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw IllegalStateException("Gagal membuka output stream gambar")

            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            uri.toString()
        } else {
            val picturesDir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_PICTURES
            )
            val targetDir = File(picturesDir, "VTrack").apply {
                if (!exists()) mkdirs()
            }
            val file = File(targetDir, fileName)
            FileOutputStream(file).use { output ->
                output.write(bytes)
                output.flush()
            }
            MediaScannerConnection.scanFile(
                this,
                arrayOf(file.absolutePath),
                arrayOf(mimeType),
                null
            )
            file.absolutePath
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val exportChannel = NotificationChannel(
                exportNotificationChannelId,
                "Export Downloads",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi file export yang siap dibuka"
            }
            val generalChannel = NotificationChannel(
                generalNotificationChannelId,
                "VTrack General",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi operasional aplikasi VTrack"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannels(listOf(exportChannel, generalChannel))
        }
    }

    private fun showExportNotification(path: String, title: String, mimeType: String) {
        val file = File(path)
        if (!file.exists()) return

        val fileUri: Uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file
        )

        val openIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(fileUri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            path.hashCode(),
            Intent.createChooser(openIntent, "Buka file export"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, exportNotificationChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Download selesai")
            .setContentText(title)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        NotificationManagerCompat.from(this).notify(path.hashCode(), notification)
    }
}

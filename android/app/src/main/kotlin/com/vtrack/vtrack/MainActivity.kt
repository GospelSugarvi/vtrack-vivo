package com.vtrack.vtrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File

class MainActivity : FlutterActivity() {
    private val exportChannel = "vtrack/export"
    private val exportNotificationChannelId = "export_downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        createNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                exportNotificationChannelId,
                "Export Downloads",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi file export yang siap dibuka"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
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

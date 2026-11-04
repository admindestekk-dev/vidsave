package com.example.vid_downloader_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.io.FileInputStream
import java.util.ArrayDeque
import java.util.Locale

class ExternalShareDownloadService : Service() {
    companion object {
        const val EXTRA_SHARED_URL = "shared_media_url"
        const val PREFERENCES = "external_share_download"
        const val PENDING_INTERSTITIAL_KEY = "pending_completion_interstitial"
        private const val CHANNEL_ID = "vidsave_share_download"
        private const val COMPLETE_CHANNEL_ID = "vidsave_share_complete"
        private const val FOREGROUND_NOTIFICATION_ID = 8432
        private const val COMPLETE_NOTIFICATION_ID = 8433
        private const val METHOD_CHANNEL = "vidsave/external_share_download"
        private const val PUBLIC_DOWNLOADS_CHANNEL = "vidsave/public_downloads"
    }

    private val pendingUrls = ArrayDeque<String>()
    private var engine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var completedDownloads = 0
    private var failedDownloads = 0
    private var lastFileName: String? = null
    private var lastError: String? = null
    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NotificationManager::class.java)
        createNotificationChannels()
        startForegroundCompat(buildProgressNotification(null, "Hazırlanıyor…"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val sharedUrl = intent?.getStringExtra(EXTRA_SHARED_URL)
        if (!sharedUrl.isNullOrBlank()) {
            pendingUrls.addLast(sharedUrl)
        } else if (pendingUrls.isEmpty() && engine == null) {
            lastError = "Paylaşılan metinde geçerli bir video bağlantısı bulunamadı."
        }

        if (engine == null) {
            startBackgroundFlutterEngine()
        }
        return START_REDELIVER_INTENT
    }

    private fun startBackgroundFlutterEngine() {
        try {
            val backgroundEngine = FlutterEngine(this)
            GeneratedPluginRegistrant.registerWith(backgroundEngine)
            engine = backgroundEngine
            installMethodChannels(backgroundEngine)
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            backgroundEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "externalShareDownloadEntrypoint",
                ),
            )
        } catch (error: Exception) {
            Log.e("VidSaveShare", "Background Flutter engine failed to start", error)
            lastError = error.localizedMessage ?: "Arka plan indirmesi başlatılamadı."
            finishDownloads(success = false)
        }
    }

    private fun installMethodChannels(backgroundEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            backgroundEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeNextUrl" -> result.success(
                        if (pendingUrls.isEmpty()) null else pendingUrls.removeFirst(),
                    )
                    "updateProgress" -> {
                        val progress = call.argument<Int>("progress")
                        val speed = call.argument<String>("speed").orEmpty()
                        updateProgress(progress, speed)
                        result.success(null)
                    }
                    "finishIfIdle" -> {
                        if (pendingUrls.isNotEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val success = call.argument<Boolean>("success") == true
                        completedDownloads = call.argument<Int>("succeeded") ?: 0
                        failedDownloads = call.argument<Int>("failed") ?: 0
                        lastFileName = call.argument<String>("fileName")
                        lastError = call.argument<String>("error") ?: lastError
                        finishDownloads(success)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            backgroundEngine.dartExecutor.binaryMessenger,
            PUBLIC_DOWNLOADS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveToDownloads") {
                result.notImplemented()
            } else {
                exportToDownloads(
                    call.argument<String>("sourcePath"),
                    call.argument<String>("fileName"),
                    result,
                )
            }
        }
    }

    private fun updateProgress(progress: Int?, speed: String) {
        val percent = progress?.coerceIn(0, 100)
        val message = if (percent == null) {
            "Video indiriliyor…"
        } else {
            "%$percent indiriliyor${if (speed.isBlank()) "" else " • $speed"}"
        }
        notificationManager.notify(
            FOREGROUND_NOTIFICATION_ID,
            buildProgressNotification(percent, message),
        )
    }

    private fun finishDownloads(success: Boolean) {
        if (success) {
            getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit()
                .putBoolean(PENDING_INTERSTITIAL_KEY, true)
                .apply()
            vibrateCompletion()
        }

        val title = if (success) "İndirme tamamlandı" else "İndirme başarısız"
        val detail = when {
            success && !lastFileName.isNullOrBlank() -> lastFileName!!
            success -> "$completedDownloads video indirildi"
            !lastError.isNullOrBlank() -> lastError!!
            failedDownloads > 0 -> "$failedDownloads bağlantı indirilemedi"
            else -> "Bağlantıyı kontrol edip tekrar deneyin."
        }
        notificationManager.notify(
            COMPLETE_NOTIFICATION_ID,
            buildCompletionNotification(title, detail),
        )
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    private fun buildProgressNotification(progress: Int?, message: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_notification_download)
            .setContentTitle("VidSave • Arka plan indirmesi")
            .setContentText(message)
            .setProgress(100, progress ?: 0, progress == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .build()
    }

    private fun buildCompletionNotification(title: String, message: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                COMPLETE_NOTIFICATION_ID,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, COMPLETE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_notification_download)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_STATUS)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Arka plan indirmeleri",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Paylaşılan videoların indirme ilerlemesi"
                setSound(null, null)
                enableVibration(false)
            },
        )
        notificationManager.createNotificationChannel(
            NotificationChannel(
                COMPLETE_CHANNEL_ID,
                "İndirme tamamlandı",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Arka plan indirmeleri tamamlandığında bildirim"
                enableVibration(false)
            },
        )
    }

    private fun vibrateCompletion() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            ?: return
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(180, VibrationEffect.DEFAULT_AMPLITUDE),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(180)
        }
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }
    }

    private fun exportToDownloads(
        sourcePath: String?,
        requestedName: String?,
        result: MethodChannel.Result,
    ) {
        try {
            require(!sourcePath.isNullOrBlank()) { "Dosya yolu eksik." }
            val source = File(sourcePath)
            require(source.isFile) { "İndirilen medya dosyası bulunamadı." }
            val name = requestedName
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.takeIf { it.isNotBlank() }
                ?: source.name

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/VidSave"
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName(name, relativePath))
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeFor(name))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: error("İndirilenler klasöründe kayıt oluşturulamadı.")
                try {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        FileInputStream(source).use { input -> input.copyTo(output) }
                    } ?: error("İndirilenler dosyası açılamadı.")
                    contentResolver.update(
                        uri,
                        ContentValues().apply {
                            put(MediaStore.MediaColumns.IS_PENDING, 0)
                        },
                        null,
                        null,
                    )
                    result.success(uri.toString())
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    throw error
                }
            } else {
                val downloadsDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                    ?: error("Uygulama indirme klasörü kullanılamıyor.")
                val destination = File(downloadsDir, name)
                FileInputStream(source).use { input ->
                    destination.outputStream().use { output -> input.copyTo(output) }
                }
                result.success(Uri.fromFile(destination).toString())
            }
        } catch (error: Exception) {
            result.error("export_failed", error.localizedMessage, null)
        }
    }

    private fun uniqueName(fileName: String, relativePath: String): String {
        var candidate = fileName
        var index = 1
        while (contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                arrayOf(candidate, relativePath),
                null,
            )?.use { it.moveToFirst() } == true
        ) {
            val dot = fileName.lastIndexOf('.')
            candidate = if (dot > 0) {
                "${fileName.substring(0, dot)}_${index++}${fileName.substring(dot)}"
            } else {
                "${fileName}_${index++}"
            }
        }
        return candidate
    }

    private fun mimeTypeFor(fileName: String): String =
        when (fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
            "mp4" -> "video/mp4"
            "mov" -> "video/quicktime"
            "webm" -> "video/webm"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "aac" -> "audio/aac"
            else -> "application/octet-stream"
        }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

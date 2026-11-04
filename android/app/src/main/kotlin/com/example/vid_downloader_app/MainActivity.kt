package com.example.vid_downloader_app

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        private const val DOWNLOADS_CHANNEL = "vidsave/public_downloads"
        private const val OVERLAY_CHANNEL = "vidsave/external_app_download_overlay"
        private const val SHARE_LIFECYCLE_CHANNEL = "vidsave/share_lifecycle"
        private const val WRITE_STORAGE_REQUEST = 4207
    }

    private var pendingLegacyExport: Pair<String, String>? = null
    private var pendingLegacyResult: MethodChannel.Result? = null
    private var pendingOverlayDownloadUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOADS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveToDownloads") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcePath = call.argument<String>("sourcePath")
            val fileName = call.argument<String>("fileName")
            if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                result.error("invalid_arguments", "Dosya yolu veya adı eksik.", null)
                return@setMethodCallHandler
            }

            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                if (pendingLegacyResult != null) {
                    result.error("export_in_progress", "Başka bir kayıt işlemi sürüyor.", null)
                    return@setMethodCallHandler
                }
                pendingLegacyExport = sourcePath to fileName
                pendingLegacyResult = result
                requestPermissions(
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    WRITE_STORAGE_REQUEST,
                )
                return@setMethodCallHandler
            }

            exportFile(sourcePath, fileName, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_LIFECYCLE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences(
                ExternalShareDownloadService.PREFERENCES,
                MODE_PRIVATE,
            )
            when (call.method) {
                "hasPendingInterstitial" -> result.success(
                    preferences.getBoolean(
                        ExternalShareDownloadService.PENDING_INTERSTITIAL_KEY,
                        false,
                    ),
                )
                "clearPendingInterstitial" -> {
                    preferences.edit()
                        .putBoolean(
                            ExternalShareDownloadService.PENDING_INTERSTITIAL_KEY,
                            false,
                        )
                        .apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OVERLAY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(
                    mapOf(
                        "canDrawOverlays" to ExternalAppOverlayPermissions.canDrawOverlays(this),
                        "hasUsageAccess" to ExternalAppOverlayPermissions.hasUsageAccess(this),
                        "enabled" to getSharedPreferences(
                            ExternalAppDownloadOverlayService.PREFERENCES,
                            MODE_PRIVATE,
                        ).getBoolean(
                            ExternalAppDownloadOverlayService.ENABLED_KEY,
                            false,
                        ),
                    ),
                )
                "requestNextPermission" -> {
                    when {
                        !ExternalAppOverlayPermissions.canDrawOverlays(this) -> {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        }
                        !ExternalAppOverlayPermissions.hasUsageAccess(this) -> {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        }
                    }
                    result.success(null)
                }
                "start" -> {
                    if (!ExternalAppOverlayPermissions.canDrawOverlays(this) ||
                        !ExternalAppOverlayPermissions.hasUsageAccess(this)
                    ) {
                        result.error(
                            "permissions_required",
                            "Ekran üstü görüntüleme ve kullanım erişimi izinleri gerekli.",
                            null,
                        )
                    } else {
                        getSharedPreferences(
                            ExternalAppDownloadOverlayService.PREFERENCES,
                            MODE_PRIVATE,
                        ).edit().putBoolean(
                            ExternalAppDownloadOverlayService.ENABLED_KEY,
                            true,
                        ).apply()
                        startOverlayService()
                        result.success(null)
                    }
                }
                "stop" -> {
                    getSharedPreferences(
                        ExternalAppDownloadOverlayService.PREFERENCES,
                        MODE_PRIVATE,
                    ).edit().putBoolean(
                        ExternalAppDownloadOverlayService.ENABLED_KEY,
                        false,
                    ).apply()
                    stopService(
                        Intent(this, ExternalAppDownloadOverlayService::class.java),
                    )
                    result.success(null)
                }
                "beginBackgroundDownload" -> {
                    val enabled = getSharedPreferences(
                        ExternalAppDownloadOverlayService.PREFERENCES,
                        MODE_PRIVATE,
                    ).getBoolean(
                        ExternalAppDownloadOverlayService.ENABLED_KEY,
                        false,
                    )
                    if (!enabled ||
                        !ExternalAppOverlayPermissions.canDrawOverlays(this) ||
                        !ExternalAppOverlayPermissions.hasUsageAccess(this)
                    ) {
                        result.error(
                            "overlay_unavailable",
                            "Dış uygulama indirme düğmesi etkin değil.",
                            null,
                        )
                    } else {
                        startOverlayService(
                            ExternalAppDownloadOverlayService.ACTION_DOWNLOAD_STARTED,
                        )
                        moveTaskToBack(true)
                        result.success(null)
                    }
                }
                "updateDownloadProgress" -> {
                    val enabled = getSharedPreferences(
                        ExternalAppDownloadOverlayService.PREFERENCES,
                        MODE_PRIVATE,
                    ).getBoolean(
                        ExternalAppDownloadOverlayService.ENABLED_KEY,
                        false,
                    )
                    val progress = call.argument<Double>("progress")
                    val speed = call.argument<String>("speed")
                    if (!enabled) {
                        result.success(null)
                    } else if (progress == null || !progress.isFinite() || speed == null) {
                        result.error(
                            "invalid_progress",
                            "İndirme ilerleme bilgisi geçersiz.",
                            null,
                        )
                    } else {
                        startService(
                            Intent(
                                this,
                                ExternalAppDownloadOverlayService::class.java,
                            ).apply {
                                action =
                                    ExternalAppDownloadOverlayService.ACTION_DOWNLOAD_PROGRESS
                                putExtra(
                                    ExternalAppDownloadOverlayService.EXTRA_PROGRESS,
                                    progress.toInt(),
                                )
                                putExtra(
                                    ExternalAppDownloadOverlayService.EXTRA_SPEED,
                                    speed,
                                )
                            },
                        )
                        result.success(null)
                    }
                }
                "finishBackgroundDownload" -> {
                    val enabled = getSharedPreferences(
                        ExternalAppDownloadOverlayService.PREFERENCES,
                        MODE_PRIVATE,
                    ).getBoolean(
                        ExternalAppDownloadOverlayService.ENABLED_KEY,
                        false,
                    )
                    val success = call.argument<Boolean>("success")
                    if (!enabled) {
                        result.success(null)
                    } else if (success == null) {
                        result.error(
                            "invalid_result",
                            "İndirme sonucu belirtilmedi.",
                            null,
                        )
                    } else {
                        startService(
                            Intent(
                                this,
                                ExternalAppDownloadOverlayService::class.java,
                            ).apply {
                                action =
                                    ExternalAppDownloadOverlayService.ACTION_DOWNLOAD_FINISHED
                                putExtra(
                                    ExternalAppDownloadOverlayService.EXTRA_SUCCESS,
                                    success,
                                )
                                putExtra(
                                    ExternalAppDownloadOverlayService.EXTRA_MESSAGE,
                                    call.argument<String>("message"),
                                )
                            },
                        )
                        result.success(null)
                    }
                }
                "getPendingDownloadUrl" -> {
                    val url = pendingOverlayDownloadUrl
                        ?: intent?.getStringExtra(ExternalAppDownloadOverlayService.EXTRA_PENDING_URL)
                    pendingOverlayDownloadUrl = null
                    intent?.removeExtra(ExternalAppDownloadOverlayService.EXTRA_PENDING_URL)
                    result.success(url)
                }
                "getPendingDownloadRequest" -> {
                    val url = pendingOverlayDownloadUrl
                        ?: intent?.getStringExtra(
                            ExternalAppDownloadOverlayService.EXTRA_PENDING_URL,
                        )
                    val shouldOpen = intent?.getBooleanExtra(
                        ExternalAppDownloadOverlayService.EXTRA_OPEN_DOWNLOAD,
                        false,
                    ) == true
                    pendingOverlayDownloadUrl = null
                    intent?.removeExtra(
                        ExternalAppDownloadOverlayService.EXTRA_PENDING_URL,
                    )
                    intent?.removeExtra(
                        ExternalAppDownloadOverlayService.EXTRA_OPEN_DOWNLOAD,
                    )
                    result.success(
                        mapOf(
                            "openDownload" to (shouldOpen || url != null),
                            "url" to url,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = intent.getStringExtra(ExternalAppDownloadOverlayService.EXTRA_PENDING_URL)
        pendingOverlayDownloadUrl = url?.takeIf { it.isNotBlank() }
    }

    override fun onResume() {
        super.onResume()
        val enabled = getSharedPreferences(
            ExternalAppDownloadOverlayService.PREFERENCES,
            MODE_PRIVATE,
        ).getBoolean(ExternalAppDownloadOverlayService.ENABLED_KEY, false)
        val hasPermissions =
            ExternalAppOverlayPermissions.canDrawOverlays(this) &&
                ExternalAppOverlayPermissions.hasUsageAccess(this)
        if (enabled && hasPermissions) {
            startOverlayService()
        } else if (enabled) {
            getSharedPreferences(
                ExternalAppDownloadOverlayService.PREFERENCES,
                MODE_PRIVATE,
            ).edit().putBoolean(
                ExternalAppDownloadOverlayService.ENABLED_KEY,
                false,
            ).apply()
            stopService(Intent(this, ExternalAppDownloadOverlayService::class.java))
        }
    }

    private fun startOverlayService(action: String? = null) {
        val serviceIntent = Intent(
            this,
            ExternalAppDownloadOverlayService::class.java,
        ).apply {
            if (action != null) this.action = action
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != WRITE_STORAGE_REQUEST) return

        val result = pendingLegacyResult ?: return
        val request = pendingLegacyExport
        pendingLegacyResult = null
        pendingLegacyExport = null
        if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            result.error("permission_denied", "İndirilenler klasörüne kayıt izni verilmedi.", null)
            return
        }
        if (request == null) {
            result.error("invalid_request", "Kayıt isteği bulunamadı.", null)
            return
        }
        exportFile(request.first, request.second, result)
    }

    private fun exportFile(
        sourcePath: String,
        requestedName: String,
        result: MethodChannel.Result,
    ) {
        try {
            val source = File(sourcePath)
            if (!source.isFile) {
                throw IllegalArgumentException("Kaynak medya dosyası bulunamadı.")
            }
            val fileName = requestedName
                .substringAfterLast('/')
                .substringAfterLast('\\')
                .ifBlank { source.name }
            val mimeType = mimeTypeFor(fileName)
            val savedLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                exportWithMediaStore(source, fileName, mimeType)
            } else {
                exportToLegacyDownloads(source, fileName, mimeType)
            }
            result.success(savedLocation)
        } catch (error: Exception) {
            result.error("export_failed", error.message ?: "Dosya kaydedilemedi.", null)
        }
    }

    private fun exportWithMediaStore(source: File, fileName: String, mimeType: String): String {
        val resolver = applicationContext.contentResolver
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/VidSave"
        val uniqueName = uniqueMediaStoreName(fileName, relativePath)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Android medya deposu dosya kaydı oluşturamadı.")

        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IllegalStateException("Android medya deposu dosyası açılamadı.")
            output.use { stream ->
                FileInputStream(source).use { input -> input.copyTo(stream) }
            }
            val publishedValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, publishedValues, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun exportToLegacyDownloads(
        source: File,
        fileName: String,
        mimeType: String,
    ): String {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "VidSave",
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Telefonun İndirilenler klasörü oluşturulamadı.")
        }
        val destination = uniqueFile(directory, fileName)
        FileInputStream(source).use { input ->
            FileOutputStream(destination).use { output -> input.copyTo(output) }
        }
        MediaScannerConnection.scanFile(
            this,
            arrayOf(destination.absolutePath),
            arrayOf(mimeType),
            null,
        )
        return destination.absolutePath
    }

    private fun uniqueMediaStoreName(fileName: String, relativePath: String): String {
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
            candidate = numberedName(fileName, index++)
        }
        return candidate
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, numberedName(fileName, index++))
        }
        return candidate
    }

    private fun numberedName(fileName: String, index: Int): String {
        val dot = fileName.lastIndexOf('.')
        return if (dot > 0) {
            "${fileName.substring(0, dot)}_$index${fileName.substring(dot)}"
        } else {
            "${fileName}_$index"
        }
    }

    private fun mimeTypeFor(fileName: String): String {
        return when (fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "wav" -> "audio/wav"
            "aac" -> "audio/aac"
            "ogg" -> "audio/ogg"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "webm" -> "video/webm"
            else -> "application/octet-stream"
        }
    }
}

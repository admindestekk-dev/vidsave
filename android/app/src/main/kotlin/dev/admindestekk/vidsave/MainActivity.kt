package dev.admindestekk.vidsave

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.ArrayDeque
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.enableEdgeToEdge(window)
    }

    companion object {
        private const val DOWNLOADS_CHANNEL = "vidsave/public_downloads"
        private const val WATERMARK_CHANNEL = "vidsave/video_watermark"
        private const val OVERLAY_CHANNEL = "vidsave/external_app_download_overlay"
        private const val WRITE_STORAGE_REQUEST = 4207
    }

    private var pendingLegacyExport: Pair<String, String>? = null
    private var pendingLegacyResult: MethodChannel.Result? = null
    private var pendingOverlayDownloadUrl: String? = null
    private var pendingOverlayOpenDownload: Boolean = false
    private var watermarkInProgress = false
    private val pendingWatermarkRequests =
        ArrayDeque<Pair<String, MethodChannel.Result>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AdOperationCounter.register(applicationContext, flutterEngine)
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
            WATERMARK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "watermarkVideo") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            if (sourcePath.isNullOrBlank()) {
                result.error("invalid_arguments", "Video dosya yolu eksik.", null)
                return@setMethodCallHandler
            }
            watermarkVideo(sourcePath, result)
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
                    if (!ExternalAppOverlayPermissions.canDrawOverlays(this)) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    }
                    result.success(null)
                }
                "start" -> {
                    if (!ExternalAppOverlayPermissions.canDrawOverlays(this)) {
                        result.error(
                            "permissions_required",
                            "Ekran üstü görüntüleme izni gerekli.",
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
                    if (!enabled || !ExternalAppOverlayPermissions.canDrawOverlays(this)) {
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
                    val shouldOpen = pendingOverlayOpenDownload
                        || (intent?.getBooleanExtra(
                            ExternalAppDownloadOverlayService.EXTRA_OPEN_DOWNLOAD,
                            false,
                        ) == true)
                    pendingOverlayDownloadUrl = null
                    pendingOverlayOpenDownload = false
                    intent?.removeExtra(
                        ExternalAppDownloadOverlayService.EXTRA_PENDING_URL,
                    )
                    intent?.removeExtra(
                        ExternalAppDownloadOverlayService.EXTRA_OPEN_DOWNLOAD,
                    )
                    val cleanIntent = Intent(this, MainActivity::class.java)
                    setIntent(cleanIntent)
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
        if (intent.getBooleanExtra(ExternalAppDownloadOverlayService.EXTRA_OPEN_DOWNLOAD, false)) {
            pendingOverlayOpenDownload = true
        }
    }

    override fun onResume() {
        super.onResume()
        ExternalAppDownloadOverlayService.isAppInForeground = true
        val enabled = getSharedPreferences(
            ExternalAppDownloadOverlayService.PREFERENCES,
            MODE_PRIVATE,
        ).getBoolean(ExternalAppDownloadOverlayService.ENABLED_KEY, false)
        val hasPermissions = ExternalAppOverlayPermissions.canDrawOverlays(this)
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

    override fun onPause() {
        ExternalAppDownloadOverlayService.isAppInForeground = false
        super.onPause()
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

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun watermarkVideo(
        sourcePath: String,
        result: MethodChannel.Result,
    ) {
        if (watermarkInProgress) {
            pendingWatermarkRequests.addLast(sourcePath to result)
            return
        }

        val source = File(sourcePath)
        if (!source.isFile) {
            result.error("source_not_found", "Filigran uygulanacak video bulunamadı.", null)
            return
        }

        val retriever = MediaMetadataRetriever()
        val videoWidth: Int
        val videoHeight: Int
        try {
            retriever.setDataSource(source.absolutePath)
            videoWidth = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            videoHeight = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
        } catch (error: Exception) {
            result.error("invalid_video", error.message ?: "Video okunamadı.", null)
            return
        } finally {
            retriever.release()
        }
        if (videoWidth <= 0 || videoHeight <= 0) {
            result.error("invalid_video", "Video boyutları okunamadı.", null)
            return
        }

        val badge = createWatermarkBitmap(videoWidth)
        val margin = min(
            videoWidth * 0.05f,
            max(16f, videoWidth * 16f / 360f),
        )
        val overlaySettings = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(
                1f - 2f * margin / videoWidth,
                -1f + 2f * margin / videoHeight,
            )
            .setOverlayFrameAnchor(1f, -1f)
            .setAlphaScale(0.75f)
            .build()
        val bitmapOverlay = BitmapOverlay.createStaticBitmapOverlay(
            badge,
            overlaySettings,
        )
        val editedMediaItem = EditedMediaItem.Builder(
            MediaItem.fromUri(Uri.fromFile(source)),
        ).setEffects(
            Effects(emptyList(), listOf(OverlayEffect(listOf(bitmapOverlay)))),
        ).build()

        val outputBase = "${source.nameWithoutExtension}_watermarked"
        var output = File(source.parentFile ?: cacheDir, "$outputBase.mp4")
        var copyIndex = 1
        while (output.exists()) {
            output = File(source.parentFile ?: cacheDir, "${outputBase}_$copyIndex.mp4")
            copyIndex++
        }

        watermarkInProgress = true
        val transformer = try {
            Transformer.Builder(this)
                .addListener(
                    object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult,
                        ) {
                            badge.recycle()
                            if (!output.isFile || output.length() == 0L) {
                                result.error(
                                    "watermark_failed",
                                    "Filigranlı video oluşturulamadı.",
                                    null,
                                )
                            } else {
                                result.success(output.absolutePath)
                            }
                            finishWatermarkVideo()
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: androidx.media3.transformer.ExportException,
                        ) {
                            badge.recycle()
                            output.delete()
                            Log.e("VidSave", "Media3 filigran işlemi başarısız oldu", exportException)
                            result.error(
                                "watermark_failed",
                                exportException.message ?: "Video filigranlanamadı.",
                                null,
                            )
                            finishWatermarkVideo()
                        }
                    },
                )
                .build()
        } catch (error: Exception) {
            badge.recycle()
            result.error("watermark_failed", error.message ?: "Media3 başlatılamadı.", null)
            finishWatermarkVideo()
            return
        }

        try {
            transformer.start(editedMediaItem, output.absolutePath)
        } catch (error: Exception) {
            badge.recycle()
            output.delete()
            result.error("watermark_failed", error.message ?: "Video filigranlanamadı.", null)
            finishWatermarkVideo()
        }
    }

    private fun finishWatermarkVideo() {
        watermarkInProgress = false
        if (pendingWatermarkRequests.isNotEmpty()) {
            val next = pendingWatermarkRequests.removeFirst()
            watermarkVideo(next.first, next.second)
        }
    }

    private fun createWatermarkBitmap(videoWidth: Int): Bitmap {
        val bitmapWidth = max(1, (videoWidth * 0.15f).roundToInt())
        val scale = bitmapWidth / 600f
        val bitmapHeight = max(1, (150f * scale).roundToInt())
        val bitmap = Bitmap.createBitmap(
            bitmapWidth,
            bitmapHeight,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)

        val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xC0181D2B.toInt()
            style = Paint.Style.FILL
        }
        val badgeBounds = RectF(2f, 2f, 598f, 148f)
        canvas.drawRoundRect(badgeBounds, 42f, 42f, backgroundPaint)

        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x99FFFFFF.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        canvas.drawRoundRect(badgeBounds, 42f, 42f, borderPaint)

        val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 11f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            shader = LinearGradient(
                38f,
                30f,
                138f,
                125f,
                intArrayOf(0xFFFF3B50.toInt(), 0xFF9B42FF.toInt()),
                null,
                Shader.TileMode.CLAMP,
            )
        }
        val arrow = Path().apply {
            moveTo(88f, 28f)
            lineTo(88f, 83f)
            moveTo(62f, 62f)
            lineTo(88f, 88f)
            lineTo(114f, 62f)
            moveTo(48f, 101f)
            lineTo(48f, 120f)
            lineTo(128f, 120f)
            lineTo(128f, 101f)
        }
        canvas.drawPath(arrow, iconPaint)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = 53f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        val label = "VidSave • HD"
        val baseline = 75f - (textPaint.ascent() + textPaint.descent()) / 2f
        canvas.drawText(label, 158f, baseline, textPaint)
        return bitmap
    }

    private fun exportFile(
        sourcePath: String,
        requestedName: String,
        result: MethodChannel.Result,
    ) {
        Thread({
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
                runOnUiThread { result.success(savedLocation) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("export_failed", error.message ?: "Dosya kaydedilemedi.", null)
                }
            }
        }, "vidsave-download-export").start()
    }

    private fun isAudioFile(fileName: String): Boolean {
        val ext = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return ext in setOf("mp3", "m4a", "wav", "aac", "ogg", "flac", "opus")
    }

    private fun isImageFile(fileName: String): Boolean {
        val ext = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return ext in setOf("jpg", "jpeg", "png", "webp", "gif")
    }

    private fun relativePathFor(fileName: String): String {
        val subDir = if (isAudioFile(fileName)) "Mp3" else if (isImageFile(fileName)) "Photo" else "Video"
        return "${Environment.DIRECTORY_DOWNLOADS}/VidSave/$subDir"
    }

    private fun exportWithMediaStore(source: File, fileName: String, mimeType: String): String {
        val resolver = applicationContext.contentResolver
        val relativePath = relativePathFor(fileName)
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

            // Cihaz genelinde medya tarayıcısını tetikle (cihazın Müzik/Dosyalar listesinde anında görünsün)
            try {
                val subDir = if (isAudioFile(fileName)) "Mp3" else if (isImageFile(fileName)) "Photo" else "Video"
                val physicalFile = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "VidSave/$subDir/$uniqueName",
                )
                if (physicalFile.exists()) {
                    MediaScannerConnection.scanFile(
                        this,
                        arrayOf(physicalFile.absolutePath),
                        arrayOf(mimeType),
                        null,
                    )
                }
            } catch (_: Exception) {}

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
        val subDir = if (isAudioFile(fileName)) "Mp3" else if (isImageFile(fileName)) "Photo" else "Video"
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "VidSave/$subDir",
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
            "flac" -> "audio/flac"
            "opus" -> "audio/opus"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "webm" -> "video/webm"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            else -> "application/octet-stream"
        }
    }
}

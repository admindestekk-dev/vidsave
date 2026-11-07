package com.example.vid_downloader_app

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import java.util.Locale

object ExternalAppOverlayPermissions {
    fun canDrawOverlays(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(context)

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }
}

class ExternalAppDownloadOverlayService : Service() {
    companion object {
        const val PREFERENCES = "external_app_download_overlay"
        const val ENABLED_KEY = "enabled"
        const val EXTRA_PENDING_URL = "pending_external_download_url"
        const val EXTRA_OPEN_DOWNLOAD = "open_external_download"
        const val ACTION_DOWNLOAD_STARTED = "download_started"
        const val ACTION_DOWNLOAD_PROGRESS = "download_progress"
        const val ACTION_DOWNLOAD_FINISHED = "download_finished"
        const val EXTRA_PROGRESS = "download_progress_value"
        const val EXTRA_SPEED = "download_speed"
        const val EXTRA_SUCCESS = "download_success"
        const val EXTRA_MESSAGE = "download_message"
        const val LAST_DOWNLOADED_URL_KEY = "last_downloaded_url"

        private const val NOTIFICATION_CHANNEL = "vidsave_external_overlay"
        private const val NOTIFICATION_ID = 8431
        private const val POLL_INTERVAL_MS = 900L

        private val NON_CONTENT_PACKAGES = setOf(
            "android",
            "com.android.systemui",
            "com.android.settings",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.google.android.packageinstaller",
            "com.android.launcher",
            "com.android.launcher3",
            "com.google.android.apps.nexuslauncher",
            "com.sec.android.app.launcher",
            "com.miui.home",
            "com.oppo.launcher",
            "com.oneplus.launcher",
            "com.google.android.youtube",
            "com.google.android.youtube.tv",
            "com.google.android.apps.youtube.music",
        )

        @Volatile
        var isAppInForeground: Boolean = false
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var showingConfirmation = false
    private var foregroundPackage: String? = null
    private var downloadActive = false
    private var downloadProgress = 0
    private var downloadSpeed = ""
    private var downloadStatusMessage: String? = null
    private var downloadProgressLabel: TextView? = null
    private var downloadProgressBar: ProgressBar? = null
    private var downloadButtonLabel: TextView? = null
    private var clipboardListener: android.content.ClipboardManager.OnPrimaryClipChangedListener? = null
    private val resetDownloadButtonRunnable = Runnable {
        val density = resources.displayMetrics.density
        downloadButtonLabel?.apply {
            text = "İNDİR"
            background = roundedBackground(Color.rgb(255, 84, 54), 24f * density)
        }
    }
    private val clearDownloadStatus = Runnable {
        downloadStatusMessage = null
        downloadProgress = 0
        downloadSpeed = ""
        removeOverlay()
        if (!isAppInForeground) {
            showDownloadButton()
        }
    }
    private val homePackageName: String? by lazy {
        packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName
    }

    private val pollForegroundApp = object : Runnable {
        override fun run() {
            if (!getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                    .getBoolean(ENABLED_KEY, false)
            ) {
                stopSelf()
                return
            }

            if (!ExternalAppOverlayPermissions.canDrawOverlays(this@ExternalAppDownloadOverlayService)) {
                stopSelf()
                return
            }

            val hasUsage = ExternalAppOverlayPermissions.hasUsageAccess(this@ExternalAppDownloadOverlayService)
            val shouldShow = if (isAppInForeground) {
                // VidSave uygulaması açıkken asla ekranda İNDİR butonu gösterme
                false
            } else if (hasUsage) {
                updateForegroundPackage()
                foregroundPackage?.let {
                    it != packageName &&
                        it != homePackageName &&
                        it !in NON_CONTENT_PACKAGES
                } == true
            } else {
                !isAppInForeground
            }
            if (shouldShow && overlayView == null) {
                if (downloadActive || downloadStatusMessage != null) {
                    showDownloadProgress()
                } else {
                    showDownloadButton()
                }
            } else if (!shouldShow && overlayView != null && !downloadActive && downloadStatusMessage == null) {
                removeOverlay()
            }
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        try {
            val clipManager = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            clipboardListener = android.content.ClipboardManager.OnPrimaryClipChangedListener {
                val url = getClipboardUrl()
                if (!url.isNullOrBlank()) {
                    if (overlayView == null) {
                        showDownloadButton()
                    }
                    highlightNewLinkReady()
                    showFormatSelectionCard(url)
                }
            }
            clipManager?.addPrimaryClipChangedListener(clipboardListener)
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, false)
                .apply()
            removeOverlay()
            handler.removeCallbacksAndMessages(null)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        if (!getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .getBoolean(ENABLED_KEY, false)
        ) {
            removeOverlay()
            handler.removeCallbacksAndMessages(null)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        when (intent?.action) {
            ACTION_DOWNLOAD_STARTED -> {
                startForeground(NOTIFICATION_ID, buildNotification())
                handler.removeCallbacks(clearDownloadStatus)
                downloadActive = true
                downloadProgress = 0
                downloadSpeed = ""
                downloadStatusMessage = null
                handler.removeCallbacks(pollForegroundApp)
                handler.post(pollForegroundApp)
                refreshDownloadOverlay()
                return START_STICKY
            }
            ACTION_DOWNLOAD_PROGRESS -> {
                downloadProgress = (intent.getIntExtra(EXTRA_PROGRESS, 0)).coerceIn(0, 100)
                downloadSpeed = intent.getStringExtra(EXTRA_SPEED).orEmpty()
                refreshDownloadOverlay()
                return START_STICKY
            }
            ACTION_DOWNLOAD_FINISHED -> {
                downloadActive = false
                downloadProgress = 100
                downloadStatusMessage = intent.getStringExtra(EXTRA_MESSAGE)
                    ?: if (intent.getBooleanExtra(EXTRA_SUCCESS, false)) {
                        "İndirme tamamlandı"
                    } else {
                        "İndirme başarısız"
                    }
                refreshDownloadOverlay()
                handler.removeCallbacks(clearDownloadStatus)
                handler.postDelayed(clearDownloadStatus, 2_000L)
                return START_STICKY
            }
        }

        if (!ExternalAppOverlayPermissions.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        handler.removeCallbacks(pollForegroundApp)
        handler.post(pollForegroundApp)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try {
            val clipManager = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            clipboardListener?.let { clipManager?.removePrimaryClipChangedListener(it) }
        } catch (_: Exception) {}
        removeOverlay()
        super.onDestroy()
    }

    private fun updateForegroundPackage() {
        val usageStats = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val events = usageStats.queryEvents(now - 60_000L, now)
        val event = UsageEvents.Event()
        var latestPackage: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val isForegroundEvent =
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                        event.eventType == UsageEvents.Event.ACTIVITY_RESUMED)
            if (isForegroundEvent) {
                latestPackage = event.packageName
            }
        }
        if (latestPackage != null) {
            foregroundPackage = latestPackage
        }
    }

    private fun highlightNewLinkReady() {
        val density = resources.displayMetrics.density
        downloadButtonLabel?.apply {
            text = "HAZIR"
            background = roundedBackground(Color.rgb(32, 184, 197), 24f * density)
        }
        handler.removeCallbacks(resetDownloadButtonRunnable)
        handler.postDelayed(resetDownloadButtonRunnable, 4_000L)
    }

    private fun showDownloadButton() {
        showingConfirmation = false
        downloadProgressLabel = null
        downloadProgressBar = null
        val density = resources.displayMetrics.density
        val root = FrameLayout(this)
        root.contentDescription = "VidSave İndir"

        val button = TextView(this).apply {
            text = "İNDİR"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground(Color.rgb(255, 84, 54), 24f * density)
            contentDescription = "İNDİR"
            setOnClickListener { showFormatSelection() }
        }
        downloadButtonLabel = button
        root.addView(
            button,
            FrameLayout.LayoutParams((76 * density).toInt(), (48 * density).toInt()),
        )

        val close = TextView(this).apply {
            text = "×"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground(Color.rgb(52, 59, 68), 16f * density)
            contentDescription = "VidSave İndir düğmesini kapat"
            setOnClickListener { closeOverlayDirectly() }
        }
        val closeParams = FrameLayout.LayoutParams(
            (32 * density).toInt(),
            (32 * density).toInt(),
            Gravity.TOP or Gravity.END,
        )
        root.addView(close, closeParams)
        addOverlay(root, (92 * density).toInt(), (64 * density).toInt())
    }

    private fun showDownloadProgress() {
        showingConfirmation = false
        val density = resources.displayMetrics.density
        val root = FrameLayout(this)
        root.contentDescription = "VidSave indirme durumu"

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                (14 * density).toInt(),
                (10 * density).toInt(),
                (14 * density).toInt(),
                (10 * density).toInt(),
            )
            background = roundedBackground(Color.rgb(30, 38, 48), 14f * density)
        }
        downloadProgressLabel = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            contentDescription = "İndirme durumu"
        }
        content.addView(
            downloadProgressLabel,
            LinearLayout.LayoutParams(
                (150 * density).toInt(),
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        downloadProgressBar = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal,
        ).apply {
            max = 100
            progress = downloadProgress
            isIndeterminate = downloadActive && downloadProgress == 0
        }
        content.addView(
            downloadProgressBar,
            LinearLayout.LayoutParams(
                (174 * density).toInt(),
                (6 * density).toInt(),
            ).apply {
                topMargin = (7 * density).toInt()
            },
        )
        root.addView(content)

        val close = TextView(this).apply {
            text = "×"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground(Color.rgb(52, 59, 68), 16f * density)
            contentDescription = "VidSave İndir düğmesini kapat"
            setOnClickListener { closeOverlayDirectly() }
        }
        root.addView(
            close,
            FrameLayout.LayoutParams(
                (32 * density).toInt(),
                (32 * density).toInt(),
                Gravity.TOP or Gravity.END,
            ),
        )
        addOverlay(root, (234 * density).toInt(), WindowManager.LayoutParams.WRAP_CONTENT)
        refreshDownloadOverlay()
    }

    private fun refreshDownloadOverlay() {
        if (overlayView == null) return
        if ((downloadActive || downloadStatusMessage != null) &&
            downloadProgressLabel == null
        ) {
            removeOverlay()
            showDownloadProgress()
            return
        }
        if (!downloadActive && downloadStatusMessage == null &&
            downloadProgressLabel != null
        ) {
            removeOverlay()
            return
        }
        val label = downloadProgressLabel ?: return
        label.text = downloadStatusMessage ?: if (downloadActive) {
            val percent = if (downloadProgress > 0) " %$downloadProgress" else ""
            val speed = if (downloadSpeed.isNotBlank()) " • $downloadSpeed" else ""
            "İndiriliyor$percent$speed"
        } else {
            "VidSave İNDİR"
        }
        downloadProgressBar?.apply {
            progress = downloadProgress
            isIndeterminate = downloadActive && downloadProgress == 0
        }
    }

    private fun closeOverlayDirectly() {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE)
            .edit()
            .putBoolean(ENABLED_KEY, false)
            .apply()
        removeOverlay()
        handler.removeCallbacksAndMessages(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun actionText(label: String, density: Float, onClick: () -> Unit) =
        TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(Color.rgb(255, 126, 64))
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(
                (12 * density).toInt(),
                (10 * density).toInt(),
                (12 * density).toInt(),
                (10 * density).toInt(),
            )
            setOnClickListener { onClick() }
        }

    private fun addOverlay(view: View, width: Int, height: Int) {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            width,
            height,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            x = (10 * resources.displayMetrics.density).toInt()
        }
        windowManager.addView(view, params)
        overlayView = view
    }

    private fun removeOverlay() {
        val view = overlayView ?: return
        try {
            windowManager.removeView(view)
        } catch (_: IllegalArgumentException) {
            // The system can remove a window while revoking overlay permission.
        }
        overlayView = null
        downloadProgressLabel = null
        downloadProgressBar = null
        downloadButtonLabel = null
        showingConfirmation = false
    }

    private fun isSupportedMediaUrl(url: String): Boolean {
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            return false
        }
        val lower = url.lowercase(Locale.ROOT)
        // YouTube kısıtlaması (Google Play politikaları gereği)
        if (lower.contains("youtube.com") || lower.contains("youtu.be")) {
            return false
        }
        return true
    }

    private fun getClipboardUrl(): String? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            ?: return null
        val clipData = clipboard.primaryClip ?: return null
        if (clipData.itemCount <= 0) return null
        val text = clipData.getItemAt(0)?.text?.toString()?.trim() ?: return null
        val matcher = android.util.Patterns.WEB_URL.matcher(text)
        if (matcher.find()) {
            val url = matcher.group()?.trim().orEmpty()
            if ((url.startsWith("http://") || url.startsWith("https://")) && isSupportedMediaUrl(url)) {
                return sanitizeUrl(url)
            }
        }
        return null
    }

    private fun sanitizeUrl(raw: String): String {
        return raw.trim().trimEnd('.', ',', ';', ')', ']', '>')
    }

    private fun detectPlatformLabel(url: String): String {
        val lower = url.lowercase(Locale.ROOT)
        return when {
            "instagram.com" in lower || "instagr.am" in lower -> "Instagram"
            "tiktok.com" in lower || "douyin.com" in lower -> "TikTok"
            "youtube.com" in lower || "youtu.be" in lower -> "YouTube"
            "facebook.com" in lower || "fb.watch" in lower || "fb.com" in lower -> "Facebook"
            "twitter.com" in lower || "x.com" in lower -> "X (Twitter)"
            "vimeo.com" in lower -> "Vimeo"
            "pinterest.com" in lower || "pin.it" in lower -> "Pinterest"
            "dailymotion.com" in lower || "dai.ly" in lower -> "Dailymotion"
            "reddit.com" in lower || "redd.it" in lower -> "Reddit"
            "soundcloud.com" in lower -> "SoundCloud"
            "threads.net" in lower -> "Threads"
            lower.contains(".mp3") || lower.contains(".m4a") || lower.contains(".aac") || lower.contains(".wav") -> "Ses / MP3"
            else -> "Web Medya"
        }
    }

    private fun formatDisplayUrl(url: String): String {
        val clean = url.removePrefix("https://").removePrefix("http://").removePrefix("www.")
        return if (clean.length > 36) clean.take(33) + "…" else clean
    }

    private fun showFormatSelection() {
        showingConfirmation = false
        val density = resources.displayMetrics.density
        val detectedUrl = getClipboardUrl()
        val prefs = getSharedPreferences(PREFERENCES, MODE_PRIVATE)
        val lastDownloaded = prefs.getString(LAST_DOWNLOADED_URL_KEY, null)

        if (detectedUrl.isNullOrBlank()) {
            // Panoda kopyalanmış link yoksa kullanıcıya bildir ve uygulamayı açarak link girişi sağla
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(
                    (14 * density).toInt(),
                    (12 * density).toInt(),
                    (14 * density).toInt(),
                    (10 * density).toInt(),
                )
                background = roundedBackground(Color.rgb(30, 38, 48), 14f * density)
            }
            card.addView(TextView(this).apply {
                text = "Bağlantı Algılanamadı"
                textSize = 14f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
            })
            card.addView(TextView(this).apply {
                text = "İzlediğiniz videoyu indirmek için lütfen videodaki 'Paylaş' simgesine dokunup 'Bağlantıyı Kopyala' deyin veya listeden 'VidSave'i seçin."
                textSize = 12f
                setTextColor(Color.LTGRAY)
                setPadding(0, (6 * density).toInt(), 0, (10 * density).toInt())
            })
            val actions = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.END
            }
            actions.addView(actionText("TAMAM", density) {
                removeOverlay()
                showDownloadButton()
            })
            actions.addView(actionText("UYGULAMAYI AÇ", density) {
                openVidSave()
                removeOverlay()
                showDownloadButton()
            })
            card.addView(actions)
            removeOverlay()
            addOverlay(card, (280 * density).toInt(), WindowManager.LayoutParams.WRAP_CONTENT)
            return
        }

        // Bağlantı mevcut, doğrudan format seçtir
        showFormatSelectionCard(detectedUrl)
    }

    private fun showFormatSelectionCard(url: String) {
        val density = resources.displayMetrics.density
        val platform = detectPlatformLabel(url)
        val shortUrl = formatDisplayUrl(url)

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                (14 * density).toInt(),
                (12 * density).toInt(),
                (14 * density).toInt(),
                (10 * density).toInt(),
            )
            background = roundedBackground(Color.rgb(30, 38, 48), 14f * density)
        }
        card.addView(TextView(this).apply {
            text = "VidSave İndir"
            textSize = 14f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
        })

        val infoRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, (4 * density).toInt(), 0, (8 * density).toInt())
        }
        val platformBadge = TextView(this).apply {
            text = platform.uppercase(Locale.ROOT)
            textSize = 9f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = roundedBackground(Color.rgb(32, 184, 197), 4f * density)
            setPadding(
                (5 * density).toInt(),
                (2 * density).toInt(),
                (5 * density).toInt(),
                (2 * density).toInt(),
            )
        }
        infoRow.addView(platformBadge)
        val urlView = TextView(this).apply {
            text = shortUrl
            textSize = 11f
            setTextColor(Color.LTGRAY)
            maxLines = 1
            setPadding((6 * density).toInt(), 0, 0, 0)
        }
        infoRow.addView(urlView)
        card.addView(infoRow)

        card.addView(TextView(this).apply {
            text = "İndirme formatını seçin:"
            textSize = 12f
            setTextColor(Color.LTGRAY)
            setPadding(0, 0, 0, (8 * density).toInt())
        })

        val buttonsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        val videoBtn = TextView(this).apply {
            text = "VİDEO (MP4)"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground(Color.rgb(255, 84, 54), 18f * density)
            setPadding(
                (12 * density).toInt(),
                (8 * density).toInt(),
                (12 * density).toInt(),
                (8 * density).toInt(),
            )
            setOnClickListener {
                startSilentDownloadFromOverlay(url, "video")
            }
        }
        val videoParams = LinearLayout.LayoutParams(
            0,
            LinearLayout.LayoutParams.WRAP_CONTENT,
            1f,
        ).apply {
            rightMargin = (6 * density).toInt()
        }
        buttonsRow.addView(videoBtn, videoParams)

        val audioBtn = TextView(this).apply {
            text = "SES (MP3)"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground(Color.rgb(32, 184, 197), 18f * density)
            setPadding(
                (12 * density).toInt(),
                (8 * density).toInt(),
                (12 * density).toInt(),
                (8 * density).toInt(),
            )
            setOnClickListener {
                startSilentDownloadFromOverlay(url, "mp3")
            }
        }
        val audioParams = LinearLayout.LayoutParams(
            0,
            LinearLayout.LayoutParams.WRAP_CONTENT,
            1f,
        ).apply {
            leftMargin = (6 * density).toInt()
        }
        buttonsRow.addView(audioBtn, audioParams)
        card.addView(buttonsRow)

        val cancelRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            setPadding(0, (4 * density).toInt(), 0, 0)
        }
        cancelRow.addView(actionText("VAZGEÇ", density) {
            removeOverlay()
            showDownloadButton()
        })
        card.addView(cancelRow)

        removeOverlay()
        addOverlay(card, (280 * density).toInt(), WindowManager.LayoutParams.WRAP_CONTENT)
    }

    private fun clearClipboardUrl() {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard?.clearPrimaryClip()
            } else {
                clipboard?.setPrimaryClip(android.content.ClipData.newPlainText("", ""))
            }
        } catch (_: Exception) {}
    }

    private fun startSilentDownloadFromOverlay(url: String, type: String) {
        // Son indirilen linki kaydet (Yeni video kontrolü için hafıza)
        getSharedPreferences(PREFERENCES, MODE_PRIVATE)
            .edit()
            .putString(LAST_DOWNLOADED_URL_KEY, url)
            .apply()

        // Her İndirme Sonrası Link Hafızasını Sıfırla (Cache Cleansing)
        clearClipboardUrl()

        // Diyalogları Otomatik Kapat (Auto-Dismiss UI):
        // Pop-up'ı salisesinde kapat
        removeOverlay()

        handler.removeCallbacks(clearDownloadStatus)
        downloadActive = true
        downloadProgress = 0
        downloadSpeed = ""
        downloadStatusMessage = null

        // Arka plan indirme servisine (ExternalShareDownloadService) doğrudan gönder
        val serviceIntent = Intent(this, ExternalShareDownloadService::class.java).apply {
            putExtra(ExternalShareDownloadService.EXTRA_SHARED_URL, url)
            putExtra(ExternalShareDownloadService.EXTRA_MEDIA_TYPE, type)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            downloadActive = false
            downloadStatusMessage = "Başlatılamadı: ${e.localizedMessage}"
            refreshDownloadOverlay()
            handler.postDelayed(clearDownloadStatus, 2_000L)
        }
    }

    private fun openVidSave() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: return

        val detectedUrl = getClipboardUrl()

        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        if (!detectedUrl.isNullOrEmpty()) {
            launchIntent.putExtra(EXTRA_PENDING_URL, detectedUrl)
        }
        launchIntent.putExtra(EXTRA_OPEN_DOWNLOAD, true)

        startActivity(launchIntent)
    }

    private fun roundedBackground(color: Int, radius: Float) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
        }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            "VidSave uygulama üstü İNDİR düğmesi",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Diğer uygulamalarda VidSave İNDİR düğmesini etkin tutar."
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_notification_download)
            .setContentTitle("VidSave İNDİR düğmesi etkin")
            .setContentText("Diğer uygulamaların üzerinde görünecek.")
            .setOngoing(true)
            .build()
    }
}

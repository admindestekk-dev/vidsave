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
import android.widget.TextView

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

        private const val NOTIFICATION_CHANNEL = "vidsave_external_overlay"
        private const val NOTIFICATION_ID = 8431
        private const val POLL_INTERVAL_MS = 900L

        private val SOCIAL_APP_PACKAGES = setOf(
            "com.facebook.katana",
            "com.facebook.lite",
            "com.instagram.android",
            "com.zhiliaoapp.musically",
            "com.ss.android.ugc.trill",
            "com.vimeo.android.videoapp",
            "com.twitter.android",
            "com.dailymotion.dailymotion",
            "com.pinterest",
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var showingConfirmation = false
    private var foregroundPackage: String? = null

    private val pollForegroundApp = object : Runnable {
        override fun run() {
            if (!getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                    .getBoolean(ENABLED_KEY, false)
            ) {
                stopSelf()
                return
            }

            if (!ExternalAppOverlayPermissions.canDrawOverlays(this@ExternalAppDownloadOverlayService) ||
                !ExternalAppOverlayPermissions.hasUsageAccess(this@ExternalAppDownloadOverlayService)
            ) {
                stopSelf()
                return
            }

            updateForegroundPackage()
            val shouldShow = foregroundPackage?.let {
                it in SOCIAL_APP_PACKAGES
            } == true
            if (shouldShow && overlayView == null) {
                showDownloadButton()
            } else if (!shouldShow && overlayView != null) {
                removeOverlay()
            }
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, false)
                .apply()
            stopSelf()
            return START_NOT_STICKY
        }

        if (!ExternalAppOverlayPermissions.canDrawOverlays(this) ||
            !ExternalAppOverlayPermissions.hasUsageAccess(this)
        ) {
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

    private fun showDownloadButton() {
        showingConfirmation = false
        val density = resources.displayMetrics.density
        val root = FrameLayout(this)
        root.contentDescription = "VidSave İndir"

        val button = TextView(this).apply {
            text = "↓"
            textSize = 28f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground(Color.rgb(255, 84, 54), 28f * density)
            contentDescription = "VidSave İndir"
            setOnClickListener { openVidSave() }
        }
        root.addView(
            button,
            FrameLayout.LayoutParams((54 * density).toInt(), (54 * density).toInt()),
        )

        val close = TextView(this).apply {
            text = "×"
            textSize = 17f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = roundedBackground(Color.rgb(52, 59, 68), 12f * density)
            contentDescription = "VidSave İndir düğmesini kapat"
            setOnClickListener { showCloseConfirmation() }
        }
        val closeParams = FrameLayout.LayoutParams(
            (24 * density).toInt(),
            (24 * density).toInt(),
            Gravity.TOP or Gravity.END,
        )
        root.addView(close, closeParams)
        addOverlay(root, (62 * density).toInt(), (62 * density).toInt())
    }

    private fun showCloseConfirmation() {
        if (showingConfirmation) return
        showingConfirmation = true
        val density = resources.displayMetrics.density
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                (16 * density).toInt(),
                (14 * density).toInt(),
                (16 * density).toInt(),
                (12 * density).toInt(),
            )
            background = roundedBackground(Color.rgb(30, 38, 48), 16f * density)
        }
        card.addView(TextView(this).apply {
            text = "VidSave İndirme Butonu Kapatılıyor"
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
        })
        card.addView(TextView(this).apply {
            text = "VidSave İndir düğmesini kapatmak istiyor musunuz?"
            textSize = 13f
            setTextColor(Color.LTGRAY)
            setPadding(0, (8 * density).toInt(), 0, (12 * density).toInt())
        })
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        actions.addView(actionText("VAZGEÇ", density) {
            showingConfirmation = false
            showDownloadButton()
        })
        actions.addView(actionText("KAPAT", density) {
            getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, false)
                .apply()
            stopSelf()
        })
        card.addView(actions)
        removeOverlay()
        addOverlay(card, (300 * density).toInt(), WindowManager.LayoutParams.WRAP_CONTENT)
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
        showingConfirmation = false
    }

    private fun openVidSave() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: return

        // Panodaki güncel bağlantıyı kontrol et
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
        val clipData = clipboard?.primaryClip
        var detectedUrl: String? = null
        if (clipData != null && clipData.itemCount > 0) {
            val text = clipData.getItemAt(0)?.text?.toString()?.trim()
            if (!text.isNullOrEmpty() && (text.startsWith("http://") || text.startsWith("https://"))) {
                detectedUrl = text
            }
        }

        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        if (!detectedUrl.isNullOrEmpty()) {
            launchIntent.putExtra(EXTRA_PENDING_URL, detectedUrl)
        }

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
            "VidSave uygulama üstü indirme düğmesi",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Seçilen sosyal uygulamalarda VidSave düğmesini etkin tutar."
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
            .setContentTitle("VidSave düğmesi etkin")
            .setContentText("Desteklenen sosyal uygulamalarda görünecek.")
            .setOngoing(true)
            .build()
    }
}

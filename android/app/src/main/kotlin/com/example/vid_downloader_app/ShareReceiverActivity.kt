package com.example.vid_downloader_app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Patterns

class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sharedText = intent?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: intent?.dataString
            ?: ""
        val matcher = Patterns.WEB_URL.matcher(sharedText)
        val url = if (matcher.find()) matcher.group().orEmpty() else ""
        val parsed = runCatching { android.net.Uri.parse(url) }.getOrNull()
        val validUrl = url.takeIf {
            parsed != null &&
                parsed.scheme in setOf("http", "https") &&
                !parsed.host.isNullOrBlank()
        }

        val serviceIntent = Intent(this, ExternalShareDownloadService::class.java)
            .putExtra(ExternalShareDownloadService.EXTRA_SHARED_URL, validUrl)
        try {
            intent?.removeExtra(Intent.EXTRA_TEXT)
            intent?.data = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (error: Exception) {
            android.util.Log.e("VidSaveShare", "Could not start share download", error)
        } finally {
            finish()
            overridePendingTransition(0, 0)
        }
    }
}

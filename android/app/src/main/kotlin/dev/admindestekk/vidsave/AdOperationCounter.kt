package dev.admindestekk.vidsave

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object AdOperationCounter {
    private const val CHANNEL = "vidsave/ad_operation_counter"
    private const val PREFERENCES = "ad_frequency"
    private const val COUNT = "successful_operations"

    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "recordSuccess" -> result.success(recordSuccess(context))
                        "getCount" -> result.success(getCount(context))
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("counter_failed", error.message, null)
                }
            }
    }

    @Synchronized
    private fun recordSuccess(context: Context): Long {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val next = preferences.getLong(COUNT, 0L) + 1
        check(preferences.edit().putLong(COUNT, next).commit()) {
            "Could not persist successful operation count"
        }
        return next
    }

    @Synchronized
    private fun getCount(context: Context): Long =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getLong(COUNT, 0L)
}

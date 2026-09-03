package dev.nirang.client.update

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object UpdateDownloadEvents : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var latest: Map<String, Any?> = mapOf("state" to "idle", "received" to 0L, "total" to 0L)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        events?.success(latest)
    }

    override fun onCancel(arguments: Any?) { sink = null }

    fun emit(value: Map<String, Any?>) {
        latest = latest.toMutableMap().apply { putAll(value) }
        mainHandler.post { sink?.success(latest) }
    }
}

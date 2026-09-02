package dev.nirang.client.update

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object UpdateDownloadEvents : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun emit(state: String, received: Long = 0, total: Long = 0) {
        mainHandler.post {
            sink?.success(mapOf("state" to state, "received" to received, "total" to total))
        }
    }
}

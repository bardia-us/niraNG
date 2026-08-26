package dev.nirang.client.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NativeEvents : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun emit(type: String, data: Any?) {
        val payload = mapOf("type" to type, "data" to data)
        mainHandler.post { sink?.success(payload) }
    }
}

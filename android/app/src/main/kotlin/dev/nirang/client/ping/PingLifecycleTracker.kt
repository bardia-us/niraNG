package dev.nirang.client.ping

import java.util.concurrent.ConcurrentHashMap

/** Tracks rows currently showing Testing so cancellation can always restore them. */
internal class PingLifecycleTracker {
    private val testing = ConcurrentHashMap.newKeySet<String>()

    @Synchronized
    fun start(serverId: String) {
        testing += serverId
    }

    @Synchronized
    fun finish(serverId: String) {
        testing -= serverId
    }

    @Synchronized
    fun cancelAll(): List<String> {
        val cancelled = testing.toList()
        testing.clear()
        return cancelled
    }
}

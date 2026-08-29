package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord

internal object SubscriptionSyncPolicy {
    /**
     * A fully parsed subscription is authoritative. A partial parse is not:
     * keep every cached profile and overlay the profiles that were parsed
     * successfully. The next complete refresh can safely remove stale entries.
     */
    fun reconcile(
        cachedServers: List<ServerRecord>,
        parsedServers: List<ServerRecord>,
        authoritative: Boolean,
    ): List<ServerRecord> {
        if (authoritative) return parsedServers
        val merged = LinkedHashMap<String, ServerRecord>()
        cachedServers.forEach { merged[it.id] = it }
        parsedServers.forEach { merged[it.id] = it }
        return merged.values.toList()
    }

    fun resetLatency(refreshedServers: List<ServerRecord>): List<ServerRecord> {
        refreshedServers.forEach { server ->
            server.pingMs = null
            server.pingStatus = "idle"
        }
        return refreshedServers
    }
}

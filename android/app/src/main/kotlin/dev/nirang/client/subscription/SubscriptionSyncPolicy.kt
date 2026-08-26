package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord

internal object SubscriptionSyncPolicy {
    fun resetLatency(refreshedServers: List<ServerRecord>): List<ServerRecord> {
        refreshedServers.forEach { server ->
            server.pingMs = null
            server.pingStatus = "idle"
        }
        return refreshedServers
    }
}

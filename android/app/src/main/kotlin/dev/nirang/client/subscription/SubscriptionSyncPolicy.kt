package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord

internal object SubscriptionSyncPolicy {
    fun carryForwardLatency(
        previousServers: List<ServerRecord>,
        refreshedServers: List<ServerRecord>,
    ): List<ServerRecord> {
        val previousById = previousServers.associateBy(ServerRecord::id)
        refreshedServers.forEach { server ->
            previousById[server.id]?.let { cached ->
                server.pingMs = cached.pingMs
                server.pingStatus = cached.pingStatus
            }
        }
        return refreshedServers
    }
}

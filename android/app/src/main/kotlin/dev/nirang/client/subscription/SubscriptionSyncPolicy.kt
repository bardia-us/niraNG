package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord

internal object SubscriptionSyncPolicy {
    /** Every successful non-empty fetch is authoritative. Malformed entries
     * are skipped individually; they must never keep stale cached profiles. */
    fun reconcile(parsedServers: List<ServerRecord>): List<ServerRecord> = parsedServers

    fun resetLatency(refreshedServers: List<ServerRecord>): List<ServerRecord> {
        refreshedServers.forEach { server ->
            server.pingMs = null
            server.pingStatus = "idle"
        }
        return refreshedServers
    }
}

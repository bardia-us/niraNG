package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubscriptionSyncPolicyTest {
    @Test
    fun `unchanged configs keep their last measured latency`() {
        val previous = server("same").apply {
            pingMs = 87
            pingStatus = "success"
        }

        val result = SubscriptionSyncPolicy.carryForwardLatency(
            previousServers = listOf(previous),
            refreshedServers = listOf(server("same")),
        ).single()

        assertEquals(87L, result.pingMs)
        assertEquals("success", result.pingStatus)
    }

    @Test
    fun `new or changed configs start without a cached ping`() {
        val previous = server("old").apply {
            pingMs = 87
            pingStatus = "success"
        }

        val result = SubscriptionSyncPolicy.carryForwardLatency(
            previousServers = listOf(previous),
            refreshedServers = listOf(server("new")),
        ).single()

        assertNull(result.pingMs)
        assertEquals("idle", result.pingStatus)
    }

    private fun server(id: String) = ServerRecord(
        id = id,
        name = id,
        country = "NL",
        protocol = "vless",
        address = "example.com",
        port = 443,
        credential = "00000000-0000-0000-0000-000000000000",
        transport = "tcp",
        security = "tls",
        parameters = emptyMap(),
    )
}

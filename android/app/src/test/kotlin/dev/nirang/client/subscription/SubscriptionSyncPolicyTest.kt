package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubscriptionSyncPolicyTest {
    @Test
    fun `partial parse overlays new profiles without removing cached profiles`() {
        val cached = listOf(server("old-a"), server("old-b"))
        val parsed = listOf(server("new-c"))

        val result = SubscriptionSyncPolicy.reconcile(cached, parsed, authoritative = false)

        assertEquals(listOf("old-a", "old-b", "new-c"), result.map { it.id })
    }

    @Test
    fun `complete parse atomically replaces cached profiles`() {
        val result = SubscriptionSyncPolicy.reconcile(
            cachedServers = listOf(server("old")),
            parsedServers = listOf(server("fresh")),
            authoritative = true,
        )

        assertEquals(listOf("fresh"), result.map { it.id })
    }

    @Test
    fun `every refreshed config returns to not tested`() {
        val refreshed = server("same").apply {
            pingMs = 87
            pingStatus = "success"
        }

        val result = SubscriptionSyncPolicy.resetLatency(listOf(refreshed)).single()

        assertNull(result.pingMs)
        assertEquals("idle", result.pingStatus)
    }

    @Test
    fun `new or changed configs start without a cached ping`() {
        val result = SubscriptionSyncPolicy.resetLatency(listOf(server("new"))).single()

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

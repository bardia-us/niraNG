package dev.nirang.client.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UnderlyingNetworkTrackerTest {
    @Test
    fun `network lost during backoff cannot publish connected`() {
        val networks = UnderlyingNetworkTracker<String>()
        networks.update("wifi-A", true)
        networks.update("wifi-B", true)
        val reconnect = networks.snapshot()
        networks.remove("wifi-A")
        networks.remove("wifi-B")
        var connected = false

        assertFalse(networks.completeReconnect(reconnect) { connected = true })
        assertFalse(connected)
    }

    @Test
    fun `same network returning after loss cannot complete old reconnect`() {
        val networks = UnderlyingNetworkTracker<String>()
        networks.update("wifi", true)
        val stale = networks.snapshot()
        networks.remove("wifi")
        networks.update("wifi", true)

        assertFalse(networks.isCurrent(stale))
        assertFalse(networks.completeReconnect(stale) { error("Old reconnect must not publish") })
        assertTrue(networks.completeReconnect(networks.snapshot()) {})
    }

    @Test
    fun `switching candidate during core start cannot publish connected`() {
        val networks = UnderlyingNetworkTracker<String>()
        networks.update("wifi", true)
        val reconnect = networks.snapshot()
        networks.update("mobile", true)
        var connected = false

        assertFalse(networks.completeReconnect(reconnect) { connected = true })
        assertFalse(connected)
    }
    @Test
    fun `Wi-Fi without internet does not displace validated mobile data`() {
        val networks = UnderlyingNetworkTracker<String>()
        networks.update("mobile", true)

        assertEquals("mobile", networks.update("wifi", false))
    }

    @Test
    fun `losing Wi-Fi keeps another available physical network`() {
        val networks = UnderlyingNetworkTracker<String>()
        networks.update("mobile", true)
        networks.update("wifi", true)

        assertEquals("mobile", networks.remove("wifi"))
    }

    @Test
    fun `validation loss on Wi-Fi returns to working mobile data`() {
        val networks = UnderlyingNetworkTracker<String>()
        networks.update("mobile", true)
        networks.update("wifi", true)

        assertEquals("mobile", networks.update("wifi", false))
    }

    @Test
    fun `unvalidated sole network is allowed for censored internet access`() {
        val networks = UnderlyingNetworkTracker<String>()

        assertEquals("wifi", networks.update("wifi", false))
        assertNull(networks.remove("wifi"))
    }
}

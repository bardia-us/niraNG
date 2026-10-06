package dev.nirang.client.vpn

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PublicIpRefreshGateTest {
    @Test
    fun `manual refresh can run again at five seconds but never sooner`() {
        var now = 0L
        val gate = PublicIpRefreshGate<String> { now }
        val first = requireNotNull(gate.tryBegin(manual = true, payload = "manual"))
        gate.complete(first)

        now = 4_999L
        assertNull(gate.tryBegin(manual = true, payload = "manual"))
        now = 5_000L
        assertNotNull(gate.tryBegin(manual = true, payload = "manual"))
    }

    @Test
    fun `manual request is rejected while initial IP diagnostic is pending`() {
        val gate = PublicIpRefreshGate<String> { 8_000L }
        val automatic = requireNotNull(gate.tryBegin(manual = false, payload = "initial"))

        assertNull(gate.tryBegin(manual = true, payload = "manual"))
        gate.complete(automatic)
        assertNotNull(gate.tryBegin(manual = true, payload = "manual"))
    }

    @Test
    fun `slow request cannot overlap another manual request after cooldown`() {
        var now = 0L
        val gate = PublicIpRefreshGate<String> { now }
        val first = requireNotNull(gate.tryBegin(manual = true, payload = "manual"))

        now = 9_000L
        assertNull(gate.tryBegin(manual = true, payload = "manual"))
        gate.complete(first)
        assertNotNull(gate.tryBegin(manual = true, payload = "manual"))
    }

    @Test
    fun `failed queue submission releases its reservation and cooldown`() {
        val gate = PublicIpRefreshGate<String> { 1_000L }
        val rejected = requireNotNull(gate.tryBegin(manual = true, payload = "manual"))

        gate.abandon(rejected)

        assertNotNull(gate.tryBegin(manual = true, payload = "manual"))
    }

    @Test
    fun `completion from abandoned request cannot release its replacement`() {
        val gate = PublicIpRefreshGate<String> { 1_000L }
        val rejected = requireNotNull(gate.tryBegin(manual = true, payload = "manual"))
        gate.abandon(rejected)
        val replacement = requireNotNull(gate.tryBegin(manual = true, payload = "manual"))

        gate.complete(rejected)
        gate.abandon(rejected)

        assertNull(gate.tryBegin(manual = true, payload = "manual"))
        gate.complete(replacement)
        assertNotNull(gate.tryBegin(manual = false, payload = "automatic"))
    }

    @Test
    fun `late IP from old physical network cannot publish after same server reconnects`() {
        val gate = PublicIpRefreshGate<String> { 0L }
        val old = requireNotNull(gate.tryBegin(manual = false, payload = "same-server"))
        var publicIp: String? = null

        gate.invalidate()
        assertFalse(gate.commitIfCurrent(old) { publicIp = "old-network-ip"; true })
        assertNull(publicIp)
    }

    @Test
    fun `busy automatic requests retain only latest reconnect and run when old check finishes`() {
        val gate = PublicIpRefreshGate<String> { 0L }
        val old = requireNotNull(gate.tryBegin(manual = false, payload = "old-network"))
        gate.invalidate()
        assertNull(gate.tryBegin(manual = false, payload = "first-reconnect"))
        assertNull(gate.tryBegin(manual = false, payload = "latest-reconnect"))

        val next = requireNotNull(gate.complete(old))

        assertEquals("latest-reconnect", next.payload)
        assertNull(gate.tryBegin(manual = true, payload = "manual"))
        assertTrue(gate.commitIfCurrent(next) { true })
        assertNull(gate.complete(next))
        assertNotNull(gate.tryBegin(manual = true, payload = "manual"))
    }

    @Test
    fun `disconnect invalidates pending reconnect without retrying it`() {
        val gate = PublicIpRefreshGate<String> { 0L }
        val old = requireNotNull(gate.tryBegin(manual = false, payload = "old-network"))
        gate.tryBegin(manual = false, payload = "reconnect")

        gate.invalidate()

        assertNull(gate.complete(old))
        assertFalse(gate.commitIfCurrent(old) { true })
    }

    @Test
    fun `completion from old request cannot commit over a new request`() {
        val gate = PublicIpRefreshGate<String> { 0L }
        val old = requireNotNull(gate.tryBegin(manual = false, payload = "old"))
        gate.complete(old)
        val next = requireNotNull(gate.tryBegin(manual = false, payload = "next"))

        assertFalse(gate.commitIfCurrent(old) { true })
        assertTrue(gate.commitIfCurrent(next) { true })
    }

    @Test
    fun `same automatic request on current network reuses its in flight check`() {
        val gate = PublicIpRefreshGate<String> { 0L }
        val current = requireNotNull(gate.tryBegin(manual = false, payload = "same-server-and-operation"))

        assertNull(gate.tryBegin(manual = false, payload = "same-server-and-operation"))

        assertNull(gate.complete(current))
        assertNotNull(gate.tryBegin(manual = true, payload = "manual"))
    }
}

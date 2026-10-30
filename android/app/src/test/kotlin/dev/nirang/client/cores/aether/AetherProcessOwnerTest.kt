package dev.nirang.client.cores.aether

import org.junit.Assert.*
import org.junit.Test

class AetherProcessOwnerTest {
    @Test fun `cancel between spawn and publish terminates stale child`() {
        val owner = AetherProcessOwner()
        val token = owner.begin()
        owner.stop()
        var stops = 0
        assertFalse(owner.install(token) { stops++ })
        assertEquals(1, stops)
        assertFalse(owner.current(token))
    }

    @Test fun `replaced operation cannot close current process`() {
        val owner = AetherProcessOwner()
        val old = owner.begin()
        var oldStops = 0
        assertTrue(owner.install(old) { oldStops++ })
        val next = owner.begin()
        var nextStops = 0
        assertTrue(owner.install(next) { nextStops++ })
        owner.finish(old)
        assertEquals(1, oldStops)
        assertEquals(0, nextStops)
        owner.stop()
        owner.stop()
        assertEquals(1, nextStops)
    }
}

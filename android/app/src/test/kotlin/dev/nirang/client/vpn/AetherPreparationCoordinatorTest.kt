package dev.nirang.client.vpn

import org.junit.Assert.*
import org.junit.Test

class AetherPreparationCoordinatorTest {
    @Test fun `completed result remains deliverable until cancellation or next operation`() {
        val owner=AetherPreparationCoordinator()
        val token=owner.begin()
        owner.finish(token)
        assertTrue(owner.validResult(token))
        owner.cancel()
        assertFalse(owner.validResult(token))
        val next=owner.begin()
        assertFalse(owner.validResult(token))
        assertTrue(owner.validResult(next))
    }
    @Test fun `stop before session assignment rejects and closes late session`() {
        val owner = AetherPreparationCoordinator()
        val token = owner.begin()
        owner.cancel()
        var stops = 0
        assertFalse(owner.install(token) { stops++ })
        assertEquals(1, stops)
        assertFalse(owner.current(token))
    }

    @Test fun `explicit stop invalidates and stops assigned preparation once`() {
        val owner = AetherPreparationCoordinator()
        val token = owner.begin()
        var stops = 0
        assertTrue(owner.install(token) { stops++ })
        owner.cancel()
        owner.cancel()
        owner.finish(token)
        assertEquals(1, stops)
        assertFalse(owner.current(token))
    }

    @Test fun `stale finish cannot stop a later independent preparation`() {
        val owner = AetherPreparationCoordinator()
        val previous = owner.begin()
        owner.cancel()
        val next = owner.begin()
        var stops = 0
        assertTrue(owner.install(next) { stops++ })
        owner.finish(previous)
        assertTrue(owner.current(next))
        assertEquals(0, stops)
        owner.finish(next)
        assertEquals(1, stops)
    }

    @Test fun `independent preparation starts without requiring an active VPN`() {
        val owner = AetherPreparationCoordinator()
        val token = owner.begin()
        assertTrue(owner.current(token))
        var stops = 0
        assertTrue(owner.install(token) { stops++ })
        assertEquals(0, stops)
        owner.finish(token)
        assertEquals(1, stops)
    }

    @Test(expected = IllegalStateException::class)
    fun `concurrent preparation is rejected until previous operation ends`() {
        val owner = AetherPreparationCoordinator()
        owner.begin()
        owner.begin()
    }
}

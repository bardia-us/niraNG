package dev.nirang.client.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectionOperationGateTest {
    @Test
    fun `disconnect during failed connect invalidates every pending callback`() {
        val gate = ConnectionOperationGate()
        val connect = gate.begin()

        gate.cancel()

        assertFalse(gate.isCurrent(connect))
    }

    @Test
    fun `rapid connect disconnect keeps only newest operation valid`() {
        val gate = ConnectionOperationGate()
        val firstConnect = gate.begin()
        gate.cancel()
        val secondConnect = gate.begin()
        gate.cancel()

        assertFalse(gate.isCurrent(firstConnect))
        assertFalse(gate.isCurrent(secondConnect))
        val latestConnect = gate.begin()
        assertTrue(gate.isCurrent(latestConnect))
    }
}

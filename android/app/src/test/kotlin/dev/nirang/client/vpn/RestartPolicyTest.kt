package dev.nirang.client.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestartPolicyTest {
    @Test
    fun `network and core settings require a service restart`() {
        assertTrue(RestartPolicy.requiresRestart(setOf("remoteDns")))
        assertTrue(RestartPolicy.requiresRestart(setOf("routingMode")))
        assertTrue(RestartPolicy.requiresRestart(setOf("vpnMtu")))
        assertTrue(RestartPolicy.requiresRestart(setOf("connectionMode")))
        assertTrue(RestartPolicy.requiresRestart(setOf("perAppPackages")))
        assertTrue(RestartPolicy.requiresRestart(setOf("directDns")))
        assertTrue(RestartPolicy.requiresRestart(setOf("observatoryEnabled")))
    }

    @Test
    fun `appearance and scheduler settings do not restart the service`() {
        assertFalse(RestartPolicy.requiresRestart(setOf("themeMode")))
        assertFalse(RestartPolicy.requiresRestart(setOf("performanceMode", "autoUpdate")))
        assertFalse(RestartPolicy.requiresRestart(emptySet()))
    }
}

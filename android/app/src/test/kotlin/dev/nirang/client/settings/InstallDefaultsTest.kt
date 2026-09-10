package dev.nirang.client.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class InstallDefaultsTest {
    @Test
    fun `fresh installs receive the new network defaults`() {
        val defaults = InstallDefaults.forExistingState(false)

        assertEquals("AsIs", defaults.domainStrategy)
        assertEquals("bypassIran", defaults.routingMode)
        assertTrue(defaults.enableIpv6)
        assertTrue(defaults.directDnsEnabled)
        assertEquals("178.22.122.100", defaults.directDns)
        assertTrue(defaults.routeOnly)
        assertFalse(defaults.blockQuic)
        assertFalse(defaults.muxEnabled)
    }

    @Test
    fun `existing installs retain the former effective defaults when keys are absent`() {
        val defaults = InstallDefaults.forExistingState(true)

        assertEquals("AsIs", defaults.domainStrategy)
        assertEquals("global", defaults.routingMode)
        assertFalse(defaults.enableIpv6)
        assertFalse(defaults.directDnsEnabled)
        assertEquals("", defaults.directDns)
        assertFalse(defaults.routeOnly)
        assertFalse(defaults.blockQuic)
        assertFalse(defaults.muxEnabled)
    }
}

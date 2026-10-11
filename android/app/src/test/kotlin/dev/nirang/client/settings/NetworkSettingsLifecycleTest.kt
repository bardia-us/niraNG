package dev.nirang.client.settings

import org.junit.Assert.*
import org.junit.Test

class NetworkSettingsLifecycleTest {
    @Test
    fun `reset keeps Telegram reminder history but restores fresh settings`() {
        val history = mapOf<String, Any>("telegramNever" to true,
            "telegramSecondShown" to true, "telegramFirstSession" to "previous-session",
            "telegramLastShown" to 123456789L)
        val prefs = MemoryPreferences(history + mapOf("installDefaultsSchema" to 5,
            "routingMode" to "global", "vpnMtu" to 1400))
        val settings = NativeSettings(prefs)
        settings.resetAll()
        settings.resetAll()
        history.forEach { (key, value) -> assertEquals(key, value, prefs.all[key]) }
        assertEquals("bypassIran", settings.routingMode)
        assertTrue(settings.enableLocalDns)
        assertEquals(1500, settings.vpnMtu)
        val fresh = MemoryPreferences()
        NativeSettings(fresh).resetAll()
        assertFalse(fresh.contains("telegramNever"))
        assertFalse(fresh.contains("telegramSecondShown"))
    }

    @Test
    fun `fresh installation persists recommended settings instead of forcing them at runtime`() {
        val prefs = MemoryPreferences()
        val settings = NativeSettings(prefs)
        assertEquals("bypassIran", settings.routingMode)
        assertFalse(settings.directDnsEnabled)
        assertFalse(settings.routeOnly)
        assertTrue(settings.enableIpv6)
        assertTrue(settings.enableLocalDns)
        assertFalse(settings.enableFakeDns)
        assertEquals("https://dns.google/dns-query", settings.remoteDns)
        for (key in listOf("enableLocalDns", "enableFakeDns", "remoteDns", "sniffingEnabled",
            "routeOnly", "directDnsEnabled", "preferIpv6", "vpnMtu", "fragmentEnabled")) {
            assertTrue("$key must be stored on first install", prefs.contains(key))
        }
        settings.update(mapOf("routeOnly" to true, "directDnsEnabled" to true, "enableIpv6" to false))
        val reopened = NativeSettings(prefs)
        assertTrue(reopened.routeOnly)
        assertTrue(reopened.directDnsEnabled)
        assertFalse(reopened.enableIpv6)
    }

    @Test
    fun `update must not overwrite an existing users network choices`() {
        for (schema in listOf(0, 5)) {
            val saved = mapOf<String, Any>(
                "installDefaultsSchema" to schema, "routingMode" to "custom",
                "routeOnly" to true, "enableLocalDns" to false, "enableFakeDns" to true,
                "directDnsEnabled" to true, "directDns" to "9.9.9.9",
                "enableIpv6" to false, "preferIpv6" to true, "vpnMtu" to 1400,
                "fragmentEnabled" to true, "muxEnabled" to true,
            )
            val prefs = MemoryPreferences(saved)
            NativeSettings(prefs)
            saved.filterKeys { it != "installDefaultsSchema" }.forEach { (key, value) ->
                assertEquals("update changed $key", value, prefs.all[key])
            }
        }
    }

    @Test
    fun `explicit reset persists the fresh profile including bypass Iran`() {
        val prefs = MemoryPreferences(mapOf("installDefaultsSchema" to 5, "routingMode" to "global",
            "routeOnly" to true, "directDnsEnabled" to true, "enableLocalDns" to false,
            "enableFakeDns" to true, "enableIpv6" to false, "vpnMtu" to 1400,
            "muxEnabled" to true, "fragmentEnabled" to true, "preferIpv6" to true))
        val settings = NativeSettings(prefs)
        val reset = settings.resetAll()
        assertEquals("bypassIran", reset["routingMode"])
        assertFalse(reset["routeOnly"] as Boolean)
        assertFalse(reset["directDnsEnabled"] as Boolean)
        assertTrue(reset["enableLocalDns"] as Boolean)
        assertFalse(reset["enableFakeDns"] as Boolean)
        assertTrue(reset["enableIpv6"] as Boolean)
        assertFalse(reset["preferIpv6"] as Boolean)
        assertFalse(reset["fragmentEnabled"] as Boolean)
        assertFalse(reset["muxEnabled"] as Boolean)
        assertEquals(1500, reset["vpnMtu"])
        assertEquals(false, prefs.all["routeOnly"])
        assertEquals(false, prefs.all["directDnsEnabled"])
        assertEquals(true, prefs.all["enableLocalDns"])
    }
}

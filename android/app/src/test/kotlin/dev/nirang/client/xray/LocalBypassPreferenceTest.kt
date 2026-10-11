package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.settings.MemoryPreferences
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.vpn.RestartPolicy
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LocalBypassPreferenceTest {
    private val server = ServerRecord("lan-test", "test", "DE", "vless", "edge.example.com",
        443, "test-id", "ws", "tls", mapOf("sni" to "edge.example.com"))

    @Test fun `saved local policy controls final routing and local name DNS in VPN and SOCKS`() {
        for (mode in listOf("global", "bypassIran", "custom")) {
            val settings = NativeSettings(MemoryPreferences(mapOf("installDefaultsSchema" to 5,
                "routingMode" to mode)))
            for (policy in listOf("auto", "bypass", "proxy")) {
                settings.update(mapOf("localBypassMode" to policy))
                assertEquals(policy, settings.toMap()["localBypassMode"])
                for (config in listOf(XrayConfigBuilder.buildVpnConfig(server, settings, listOf("2.144.0.0/14")),
                    XrayConfigBuilder.buildProxyConfig(server, settings, listOf("2.144.0.0/14")))) {
                    val root = JSONObject(config)
                    val rules = root.getJSONObject("routing").getJSONArray("rules")
                    val lanRules = (0 until rules.length()).map(rules::getJSONObject).filter {
                        it.optJSONArray("ip")?.toString()?.contains("192.168.0.0/16") == true ||
                            it.optJSONArray("domain")?.toString()?.contains("full:localhost") == true
                    }
                    assertEquals(2, lanRules.size)
                    assertTrue(lanRules.all { it.getString("outboundTag") == if (policy == "proxy") "proxy" else "direct" })
                    val dns = root.getJSONObject("dns").getJSONArray("servers")
                    val localResolvers = (0 until dns.length()).mapNotNull(dns::optJSONObject).filter {
                        it.optString("address") == "localhost"
                    }
                    assertEquals(if (policy == "proxy") 0 else 1, localResolvers.size)
                    assertEquals("proxy", rules.getJSONObject(0).getString("outboundTag"))
                }
            }
        }
    }

    @Test fun `auto preserves existing bypass and invalid values are rejected without writing`() {
        val prefs = MemoryPreferences(mapOf("installDefaultsSchema" to 5, "routeOnly" to true))
        val settings = NativeSettings(prefs)
        assertEquals("auto", settings.toMap()["localBypassMode"])
        settings.update(mapOf("localBypassMode" to "proxy"))
        assertEquals("proxy", NativeSettings(prefs).toMap()["localBypassMode"])
        assertThrows(IllegalArgumentException::class.java) { settings.update(mapOf("localBypassMode" to "invalid")) }
        assertEquals("proxy", settings.toMap()["localBypassMode"])
        assertTrue(RestartPolicy.requiresRestart(setOf("localBypassMode")))
        assertEquals(true, settings.toMap()["routeOnly"])
        settings.resetAll()
        assertEquals("auto", settings.toMap()["localBypassMode"])
    }
}

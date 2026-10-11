package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.settings.MemoryPreferences
import dev.nirang.client.settings.NativeSettings
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class RouteOnlyPreferenceTest {
    @Test
    fun `all routing modes respect the saved routeOnly switch in final core JSON`() {
        for (mode in listOf("global", "bypassIran", "custom")) {
            for (routeOnly in listOf(false, true)) {
                val prefs = MemoryPreferences(mapOf("installDefaultsSchema" to 5,
                    "routingMode" to mode, "routeOnly" to routeOnly, "sniffingEnabled" to true))
                val settings = NativeSettings(prefs)
                val root = JSONObject(XrayConfigBuilder.buildVpnConfig(server, settings, listOf("2.144.0.0/14")))
                val inbounds = root.getJSONArray("inbounds")
                for (index in 0 until inbounds.length()) {
                    val inbound = inbounds.getJSONObject(index)
                    if (!inbound.has("sniffing")) continue
                    assertEquals("$mode ${inbound.getString("tag")} ignored switch",
                        routeOnly, inbound.getJSONObject("sniffing").getBoolean("routeOnly"))
                }
                settings.update(mapOf("routeOnly" to !routeOnly))
                val changed = JSONObject(XrayConfigBuilder.buildProxyConfig(server, settings, listOf("2.144.0.0/14")))
                assertEquals(!routeOnly, changed.getJSONArray("inbounds").getJSONObject(0)
                    .getJSONObject("sniffing").getBoolean("routeOnly"))
            }
        }
    }

    private val server = ServerRecord("route-only-test", "test", "DE", "vless", "edge.example.com",
        443, "test-id", "ws", "tls", mapOf("sni" to "edge.example.com"))
}

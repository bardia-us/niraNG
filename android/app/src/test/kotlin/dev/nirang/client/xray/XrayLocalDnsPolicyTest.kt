package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayLocalDnsPolicyTest {
    @Test
    fun `remote DNS has a dedicated proxy route before Iran or custom bypass rules`() {
        val dns = XrayConfigBuilder.buildDnsSettings("https://resolver.example.ir/dns-query",
            false, "", "bypassIran", "", false, true)
        assertEquals("remote-dns", dns.optString("tag"))
        for (mode in listOf("global", "bypassIran", "custom")) {
            val rules = XrayConfigBuilder.buildRouting(mode, customDomains = "domain:resolver.example.ir",
                iranCidrs = listOf("2.144.0.0/14")).getJSONArray("rules")
            val first = rules.getJSONObject(0)
            assertEquals("remote-dns", first.getJSONArray("inboundTag").getString(0))
            assertEquals("proxy", first.getString("outboundTag"))
            assertFalse(first.has("domain"))
            assertFalse(first.has("ip"))
        }
    }

    @Test
    fun `Google DoH trailing slash that returns HTTP 404 is corrected in final DNS JSON`() {
        for (address in listOf("https://dns.google/dns-query/", "https+local://dns.google/dns-query/")) {
            val dns = XrayConfigBuilder.buildDnsSettings(address, false, "", "global", "", false, true)
            assertEquals(address.removeSuffix("/"), dns.getJSONArray("servers").getString(1))
        }
    }

    @Test
    fun `custom resolver paths query parameters and direct policy must remain intact`() {
        val custom = "https://resolver.example/dns-query/?token=test%2Bvalue"
        val dns = XrayConfigBuilder.buildDnsSettings(custom, true,
            "https://dns.google/dns-query/", "bypassIran", "", false, true)
        assertEquals(custom, dns.getJSONArray("servers").getString(2))
        assertEquals("https+local://dns.google/dns-query", dns.getJSONArray("servers")
            .getJSONObject(1).getString("address"))
    }

    @Test
    fun `DNS interception must not forward non address queries to the physical resolver`() {
        val root = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
        val outbounds = root.getJSONArray("outbounds")
        val dns = (0 until outbounds.length()).map(outbounds::getJSONObject)
            .single { it.getString("tag") == "dns-out" }

        assertEquals("dns", dns.getString("protocol"))
        // The bundled core maps legacy skip to direct for HTTPS, SVCB and
        // other non-A/AAAA queries. With no override, its default policy
        // handles A/AAAA locally and returns an empty answer for other types,
        // matching v2rayNG/PattNG without leaking or waiting for physical DNS.
        assertFalse("non-IP DNS must not bypass the configured resolver",
            dns.optJSONObject("settings")?.optString("nonIPQuery") == "skip")
        assertFalse("DNS must not rewrite queries to a physical resolver",
            dns.optJSONObject("settings")?.has("rewriteAddress") == true)
    }

    @Test
    fun `local DNS interception remains opt in and covers TCP and UDP from VPN`() {
        for (enabled in listOf(false, true)) {
            val rules = XrayConfigBuilder.buildRouting("global", enableLocalDns = enabled)
                .getJSONArray("rules")
            val dns = (0 until rules.length()).map(rules::getJSONObject)
                .filter { it.getString("outboundTag") == "dns-out" }
            assertEquals(if (enabled) 1 else 0, dns.size)
            if (enabled) {
                assertEquals("53", dns.single().getString("port"))
                assertEquals("tcp,udp", dns.single().getString("network"))
                assertEquals("tun-in", dns.single().getJSONArray("inboundTag").getString(0))
            }
        }
    }

    @Test
    fun `DoH and IPv6 selection are preserved without enabling fake DNS`() {
        val dns = XrayConfigBuilder.buildDnsSettings(
            "https://dns.google/dns-query", false, "", "global", "", false, true,
        )
        assertEquals("UseIP", dns.getString("queryStrategy"))
        val servers = dns.getJSONArray("servers")
        assertEquals("https://dns.google/dns-query", servers.getString(1))
        assertFalse((0 until servers.length()).any { servers.optString(it) == "fakedns" })

        val root = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
        val tls = root.getJSONArray("outbounds").getJSONObject(0)
            .getJSONObject("streamSettings").getJSONObject("tlsSettings")
        assertEquals("chrome", tls.getString("fingerprint"))
        assertEquals("cloudflare-ech.com+udp://1.1.1.1", tls.getString("echConfigList"))
        assertTrue(tls.getJSONArray("alpn").toString().contains("h2"))
    }

    private val server = ServerRecord(
        "dns-policy-test", "DNS policy test", "", "vless", "edge.example.com", 443,
        "test-id", "ws", "tls", mapOf(
            "fp" to "chrome", "alpn" to "h2,http/1.1",
            "ech" to "cloudflare-ech.com+udp://1.1.1.1",
        ),
    )
}

package dev.nirang.client.xray

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayAdvancedSettingsTest {
    @Test
    fun `direct DNS uses local transport only for direct domain rules`() {
        val dns = XrayConfigBuilder.buildDnsSettings(
            remoteDns = "https://dns.google/dns-query",
            directDnsEnabled = true,
            directDns = "https://cloudflare-dns.com/dns-query",
            routingMode = "bypassIran",
            customDomains = "",
            fakeDns = false,
            enableIpv6 = true,
        )
        val direct = dns.getJSONArray("servers").getJSONObject(0)
        assertEquals("https+local://cloudflare-dns.com/dns-query", direct.getString("address"))
        assertTrue((0 until direct.getJSONArray("domains").length())
            .map { direct.getJSONArray("domains").getString(it) }.contains("domain:ir"))
        assertTrue(direct.getBoolean("skipFallback"))
        assertEquals("UseIP", dns.getString("queryStrategy"))
    }

    @Test
    fun `disabled direct DNS adds no synthetic resolver`() {
        val dns = XrayConfigBuilder.buildDnsSettings(
            "1.1.1.1", false, "9.9.9.9", "global", "", false, false,
        )
        assertFalse(dns.getJSONArray("servers").get(0) is org.json.JSONObject)
    }

    @Test
    fun `observatory uses the supported leastPing and leastLoad schema`() {
        val sections = XrayConfigBuilder.buildObservatorySections("3m", "5m", "HEAD", 2, "30s")
        assertEquals("3m", sections.getJSONObject("observatory").getString("probeInterval"))
        val ping = sections.getJSONObject("burstObservatory").getJSONObject("pingConfig")
        assertEquals("5m", ping.getString("interval"))
        assertEquals("HEAD", ping.getString("httpMethod"))
        assertEquals(2, ping.getInt("sampling"))
        assertEquals("30s", ping.getString("timeout"))
    }
}

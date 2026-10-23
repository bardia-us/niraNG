package dev.nirang.client.xray

import dev.nirang.client.settings.MemoryPreferences
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.ServerProfileOverrides
import dev.nirang.client.subscription.SubscriptionParser
import java.net.URLEncoder
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class XrayEchOutboundPolicyTest {
    @Test
    fun `PattNG public h2c helper is linked and appended unchanged in every connection builder`() {
        val source = SubscriptionParser.parse(SOURCE).single()
        val server = ServerProfileOverrides().updated(source, mapOf(
            "echConfigList" to "h2c://1.1.1.1/dns-query", "echOutbound" to HELPER,
        )).apply(listOf(source)).single()
        val settings = NativeSettings(MemoryPreferences(mapOf("routingMode" to "global")))
        listOf(
            XrayConfigBuilder.buildVpnConfig(server, settings),
            XrayConfigBuilder.buildProxyConfig(server, settings),
            XrayConfigBuilder.buildProbeConfig(server, settings),
            XrayConfigBuilder.buildSafeFallbackConfig(server),
        ).forEach { config ->
            val outbounds = JSONObject(config).getJSONArray("outbounds")
            val mainTls = outbounds.getJSONObject(0).getJSONObject("streamSettings").getJSONObject("tlsSettings")
            assertEquals("h2c://1.1.1.1/dns-query", mainTls.getString("echConfigList"))
            assertEquals("tls-repack-dns", mainTls.getJSONObject("echSockopt").getString("dialerProxy"))
            assertFalse(mainTls.has("echOutbound"))
            assertEquals(5, outbounds.length())
            val helper = outbounds.getJSONObject(4)
            assertEquals(JSONObject(HELPER).toString(), helper.toString())
            assertEquals("direct", helper.getString("protocol"))
            assertEquals("1.1.1.1:443", helper.getJSONObject("settings").getString("redirect"))
            val tls = helper.getJSONObject("streamSettings").getJSONObject("tlsSettings")
            assertEquals("www.microsoft.com", tls.getString("serverName"))
            assertEquals("fromMitM,www.microsoft.com", tls.getString("verifyPeerCertByName"))
            assertEquals("fromMitM", tls.getJSONArray("alpn").getString(0))
            assertEquals("chrome", tls.getString("fingerprint"))
        }
    }

    @Test
    fun `share link h2c helper survives import and append as a JSON object`() {
        val encoded = URLEncoder.encode(HELPER, Charsets.UTF_8.name()).replace("+", "%20")
        val server = SubscriptionParser.parse("$SOURCE&echConfigList=h2c%3A%2F%2F1.1.1.1%2Fdns-query&echOutbound=$encoded").single()
        val config = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
        assertEquals(JSONObject(HELPER).toString(), config.getJSONArray("outbounds").getJSONObject(4).toString())
    }

    @Test
    fun `invalid missing and recursive helper configuration fails closed`() {
        val source = SubscriptionParser.parse(SOURCE).single()
        listOf(
            mapOf("echConfigList" to "h2c://1.1.1.1/dns-query"),
            mapOf("echOutbound" to HELPER),
            mapOf("echConfigList" to "h2c://1.1.1.1/dns-query", "echOutbound" to "[]"),
            mapOf("echConfigList" to "h2c://1.1.1.1/dns-query", "echOutbound" to HELPER.replace("tls-repack-dns", "proxy-loop")),
            mapOf("echConfigList" to "h2c://1.1.1.1/dns-query", "echOutbound" to HELPER.replace("\"security\": \"tls\"", "\"security\": \"tls\", \"sockopt\": {\"dialerProxy\":\"proxy\"}")),
        ).forEach { parameters ->
            assertThrows(IllegalArgumentException::class.java) {
                XrayConfigBuilder.buildSafeFallbackConfig(source.copy(parameters = source.parameters + parameters))
            }
        }
    }

    private companion object {
        const val SOURCE = "vless://00000000-0000-4000-8000-000000000001@edge.example.com:443?security=tls&type=ws&sni=origin.example.com&fp=chrome"
        val HELPER = """
            {
              "tag": "tls-repack-dns",
              "protocol": "direct",
              "settings": { "redirect": "1.1.1.1:443" },
              "streamSettings": {
                "security": "tls",
                "tlsSettings": {
                  "serverName": "www.microsoft.com",
                  "verifyPeerCertByName": "fromMitM,www.microsoft.com",
                  "alpn": ["fromMitM"],
                  "fingerprint": "chrome"
                }
              }
            }
        """.trimIndent()
    }
}

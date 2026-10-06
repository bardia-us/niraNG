package dev.nirang.client.xray

import dev.nirang.client.subscription.SubscriptionParser
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class XrayEchConfigTest {
    @Test
    fun `ECH aliases preserve raw and encoded plus from share link through TLS JSON`() {
        listOf("ech", "echConfigList").forEach { key ->
            listOf("cloudflare-ech.com+udp://1.1.1.1", "cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1").forEach { value ->
                val server = SubscriptionParser.parse("vless://test-id@edge.example.com:443?security=tls&type=ws&$key=$value&fp=chrome&alpn=h2,http%2F1.1&cs=TLS_AES_128_GCM_SHA256").single()
                val tls = stream(server).getJSONObject("tlsSettings")
                assertEquals("cloudflare-ech.com+udp://1.1.1.1", tls.getString("echConfigList"))
                assertEquals("chrome", tls.getString("fingerprint"))
                assertEquals("h2", tls.getJSONArray("alpn").getString(0))
                assertEquals("TLS_AES_128_GCM_SHA256", tls.getString("cipherSuites"))
            }
        }
    }

    @Test
    fun `fixed Base64 ECH remains byte exact including plus slash and padding`() {
        val server = SubscriptionParser.parse("trojan://password@edge.example.com:443?security=tls&ech=AF7+DQBa/AAA==").single()
        assertEquals("AF7+DQBa/AAA==", stream(server).getJSONObject("tlsSettings").getString("echConfigList"))
    }

    @Test
    fun `VMess JSON supports ECH config and share alias`() {
        listOf("ech", "echConfigList").forEach { key ->
            val payload = JSONObject().put("add", "edge.example.com").put("port", 443).put("id", "test-id")
                .put("net", "ws").put("tls", "tls").put(key, "cloudflare-ech.com+udp://1.1.1.1")
            val server = SubscriptionParser.parse("vmess://" + Base64.getEncoder().encodeToString(payload.toString().toByteArray())).single()
            assertEquals("cloudflare-ech.com+udp://1.1.1.1", stream(server).getJSONObject("tlsSettings").getString("echConfigList"))
        }
    }

    @Test
    fun `absent or empty ECH preserves previous TLS JSON and never leaks into Reality or plaintext`() {
        val base = "vless://test-id@edge.example.com:443?security=tls&type=ws&fp=chrome"
        val expected = stream(SubscriptionParser.parse(base).single()).getJSONObject("tlsSettings")
        assertFalse(expected.has("echConfigList"))
        assertEquals(expected.toString(), stream(SubscriptionParser.parse("$base&ech=").single()).getJSONObject("tlsSettings").toString())
        listOf("none", "reality").forEach { security ->
            val result = stream(SubscriptionParser.parse("vless://test-id@edge.example.com:443?security=$security&ech=AF7+DQBa/AAA==&pbk=key").single())
            assertFalse(result.has("tlsSettings"))
            assertFalse(result.toString().contains("echConfigList"))
        }
    }

    private fun stream(server: dev.nirang.client.model.ServerRecord): JSONObject =
        JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server)).getJSONArray("outbounds")
            .getJSONObject(0).getJSONObject("streamSettings")
}

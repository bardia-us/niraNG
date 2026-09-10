package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayProtocolConfigTest {
    @Test
    fun `Shadowsocks maps method password and server into real outbound`() {
        val outbound = outbound(server("shadowsocks", "secret", mapOf("method" to "chacha20-ietf-poly1305")))
        assertEquals("shadowsocks", outbound.getString("protocol"))
        val target = outbound.getJSONObject("settings").getJSONArray("servers").getJSONObject(0)
        assertEquals("chacha20-ietf-poly1305", target.getString("method"))
        assertEquals("secret", target.getString("password"))
        assertEquals("example.com", target.getString("address"))
    }

    @Test
    fun `SOCKS and HTTP credentials map to outbound users`() {
        for (protocol in listOf("socks", "http")) {
            val outbound = outbound(server(protocol, "pass", mapOf("username" to "user")))
            val user = outbound.getJSONObject("settings").getJSONArray("servers").getJSONObject(0)
                .getJSONArray("users").getJSONObject(0)
            assertEquals("user", user.getString("user"))
            assertEquals("pass", user.getString("pass"))
        }
    }

    @Test
    fun `Hysteria2 maps to version two Hysteria transport`() {
        val outbound = outbound(server("hysteria2", "auth", mapOf("version" to "2"), "hysteria", "tls"))
        assertEquals("hysteria", outbound.getString("protocol"))
        assertEquals(2, outbound.getJSONObject("settings").getInt("version"))
        assertEquals("auth", outbound.getJSONObject("streamSettings").getJSONObject("hysteriaSettings").getString("auth"))
    }

    @Test
    fun `QUIC routing is opt in and independent of proxy protocol`() {
        val allowed = XrayConfigBuilder.buildRouting("global", enableLocalDns = false)
        assertFalse(hasUdp443Block(allowed))

        val blocked = XrayConfigBuilder.buildRouting("global", enableLocalDns = false, blockQuic = true)
        assertTrue(hasUdp443Block(blocked))
    }

    @Test
    fun `Mux remains opt in and is emitted only for compatible outbounds`() {
        assertFalse(XrayConfigBuilder.buildMux(server("vless", "id", emptyMap()), false).getBoolean("enabled"))
        assertTrue(XrayConfigBuilder.buildMux(server("vless", "id", emptyMap()), true).getBoolean("enabled"))
        assertTrue(XrayConfigBuilder.buildMux(server("vmess", "id", emptyMap()), true).getBoolean("enabled"))
        assertFalse(
            XrayConfigBuilder.buildMux(
                server("vless", "id", emptyMap(), transport = "xhttp"),
                true,
            ).getBoolean("enabled"),
        )
        assertFalse(
            XrayConfigBuilder.buildMux(
                server("vless", "id", mapOf("flow" to "xtls-rprx-vision")),
                true,
            ).getBoolean("enabled"),
        )
        assertFalse(
            XrayConfigBuilder.buildMux(
                server("shadowsocks", "secret", mapOf("method" to "chacha20-ietf-poly1305")),
                true,
            ).getBoolean("enabled"),
        )
    }

    private fun config(server: ServerRecord) = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
    private fun hasUdp443Block(routing: JSONObject): Boolean {
        val rules = routing.getJSONArray("rules")
        return (0 until rules.length()).map(rules::getJSONObject).any {
            it.optString("network") == "udp" && it.optString("port") == "443" &&
                it.optString("outboundTag") == "blocked"
        }
    }
    private fun outbound(server: ServerRecord) = config(server).getJSONArray("outbounds").getJSONObject(0)
    private fun server(protocol: String, credential: String, parameters: Map<String, String>, transport: String = "tcp", security: String = "none") = ServerRecord(
        "id", "Test", "", protocol, "example.com", 443, credential, transport, security, parameters,
    )
}

package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayPattCompatibilityTest {
    @Test
    fun `Android TUN explicitly keeps legacy name required by Xray 26_8`() {
        val config = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server()))
        val tunInbound = config.getJSONArray("inbounds")
            .objects()
            .single { it.getString("tag") == "tun-in" }
        val settings = tunInbound.getJSONObject("settings")

        assertEquals(XrayConfigBuilder.ANDROID_TUN_CONFIG_NAME, settings.getString("name"))
        assertEquals("xray0", settings.getString("name"))
        assertEquals(1500, settings.getInt("mtu"))
        assertFalse(settings.has("autoSystemRoutingTable"))
        assertFalse(settings.has("autoOutboundsInterface"))
    }

    @Test
    fun `VLESS WS TLS CDN fields map to the generated stream settings`() {
        val stream = streamSettings(
            server(
                protocol = "vless",
                parameters = mapOf(
                    "host" to "cdn.example.com",
                    "sni" to "origin.example.com",
                    "path" to "/edge?ed=2560",
                    "alpn" to "http/1.1,h2",
                    "fp" to "unsafe",
                    "cs" to "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384",
                    "allowInsecure" to "1",
                    "fm" to FINAL_MASK,
                ),
            ),
        )

        assertEquals("ws", stream.getString("network"))
        assertEquals("/edge?ed=2560", stream.getJSONObject("wsSettings").getString("path"))
        assertEquals(
            "cdn.example.com",
            stream.getJSONObject("wsSettings").getString("host"),
        )
        val tls = stream.getJSONObject("tlsSettings")
        assertEquals("origin.example.com", tls.getString("serverName"))
        assertEquals("unsafe", tls.getString("fingerprint"))
        assertEquals("TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384", tls.getString("cipherSuites"))
        // The current bundled Xray schema rejects allowInsecure. The parser
        // keeps it for compatibility, but the builder must not break startup.
        assertFalse(tls.has("allowInsecure"))
        assertEquals("fragment", stream.getJSONObject("finalmask").getJSONArray("tcp")
            .getJSONObject(0).getString("type"))
        assertFalse(stream.has("fragment"))
    }

    @Test
    fun `Trojan WS TLS keeps removed insecure alias out of generated schema`() {
        val stream = streamSettings(
            server(
                protocol = "trojan",
                credential = "password",
                parameters = mapOf(
                    "host" to "edge.example.net",
                    "path" to "/trojan-ws",
                    "sni" to "edge.example.net",
                    "insecure" to "true",
                ),
            ),
        )

        assertEquals("ws", stream.getString("network"))
        assertFalse(stream.getJSONObject("tlsSettings").has("allowInsecure"))
    }

    @Test
    fun `XHTTP remains mapped without mixing FinalMask into fragment settings`() {
        val stream = streamSettings(
            server(
                transport = "splithttp",
                parameters = mapOf("host" to "cdn.example.com", "path" to "/xhttp", "mode" to "auto"),
            ),
        )

        assertEquals("xhttp", stream.getString("network"))
        assertEquals("/xhttp", stream.getJSONObject("xhttpSettings").getString("path"))
        assertFalse(stream.has("finalmask"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `unsafe fingerprint is rejected for Reality`() {
        XrayConfigBuilder.buildSafeFallbackConfig(
            server(
                security = "reality",
                transport = "xhttp",
                parameters = mapOf("sni" to "example.com", "pbk" to "public-key", "fp" to "unsafe"),
            ),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `invalid FinalMask is rejected before Xray starts`() {
        XrayConfigBuilder.buildSafeFallbackConfig(server(parameters = mapOf("fm" to "[invalid]")))
    }

    @Test
    fun `Fragment maps independently to FinalMask tcp schema`() {
        val fragment = XrayConfigBuilder.buildFragmentSettings("tlshello", "50-100", "10-20", 10)
        val entry = fragment.getJSONArray("tcp").getJSONObject(0)
        assertEquals("fragment", entry.getString("type"))
        val settings = entry.getJSONObject("settings")
        assertEquals("tlshello", settings.getString("packets"))
        assertEquals("50-100", settings.getString("length"))
        assertEquals("10-20", settings.getString("delay"))
        assertEquals(10, settings.getInt("maxSplit"))
    }

    @Test
    fun `profile FinalMask preserves ordered lengths and delays without merging Fragment`() {
        val raw =
            "{\"tcp\":[{\"type\":\"fragment\",\"settings\":{" +
                "\"packets\":\"tlshello\",\"lengths\":[\"5\",\"94\",\"1\"]," +
                "\"delays\":[\"0\"],\"maxSplit\":\"0\"}},{\"type\":\"fragment\",\"settings\":{" +
                "\"packets\":\"1-1\",\"lengths\":[\"109\",\"1\"]," +
                "\"delays\":[\"1\"],\"maxSplit\":\"355\"}}]}"
        val stream = streamSettings(server(parameters = mapOf("fm" to raw)))
        val tcp = stream.getJSONObject("finalmask").getJSONArray("tcp")

        assertEquals(2, tcp.length())
        assertEquals("5", tcp.getJSONObject(0).getJSONObject("settings").getJSONArray("lengths").getString(0))
        assertEquals("94", tcp.getJSONObject(0).getJSONObject("settings").getJSONArray("lengths").getString(1))
        assertEquals("0", tcp.getJSONObject(0).getJSONObject("settings").getJSONArray("delays").getString(0))
        assertEquals("355", tcp.getJSONObject(1).getJSONObject("settings").getString("maxSplit"))
        assertFalse(stream.has("fragment"))
    }

    private fun streamSettings(server: ServerRecord): JSONObject {
        val config = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
        return config.getJSONArray("outbounds").getJSONObject(0).getJSONObject("streamSettings")
    }

    private fun server(
        protocol: String = "vless",
        credential: String = "00000000-0000-4000-8000-000000000001",
        transport: String = "ws",
        security: String = "tls",
        parameters: Map<String, String> = emptyMap(),
    ) = ServerRecord(
        id = "test-$protocol-$transport",
        name = "Test",
        country = "NL",
        protocol = protocol,
        address = "104.16.0.1",
        port = 443,
        credential = credential,
        transport = transport,
        security = security,
        parameters = parameters,
    )

    private companion object {
        const val FINAL_MASK =
            "{\"tcp\":[{\"type\":\"fragment\",\"settings\":{\"packets\":\"tlshello\",\"length\":\"1-1\",\"delay\":\"1-2\"}}]}"
    }

    private fun org.json.JSONArray.objects(): List<JSONObject> =
        (0 until length()).map(::getJSONObject)
}

package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import org.junit.Assert.*
import org.junit.Test

class ServerProfileSettingsTest {
    @Test
    fun `TLS editor receives actual profile values without unmasked credentials`() {
        val metadata = server(parameters = mapOf(
            "sni" to "origin.example.com", "fp" to "unsafe", "cs" to "TLS_AES_128_GCM_SHA256",
            "fm" to "{\"tcp\":[]}", "alpn" to "h2,http/1.1", "allowInsecure" to "1",
        )).safeMetadata("server-1")
        assertEquals("unsafe", metadata["fingerprint"])
        assertEquals("TLS_AES_128_GCM_SHA256", metadata["cipherSuites"])
        assertEquals("{\"tcp\":[]}", metadata["finalMask"])
        assertEquals("h2,http/1.1", metadata["alpn"])
        assertEquals(true, metadata["allowInsecure"])
        assertEquals(true, metadata["profileEditable"])
        assertFalse(metadata.values.contains("private-credential"))
    }

    @Test
    fun `QUIC and plaintext profiles do not offer incompatible TLS editor`() {
        assertEquals(false, server(protocol = "hysteria2", transport = "hysteria").safeMetadata(null)["profileEditable"])
        assertEquals(false, server(security = "none").safeMetadata(null)["profileEditable"])
    }

    @Test
    fun `profile FinalMask does not apply to Reality`() {
        val stream = org.json.JSONObject(dev.nirang.client.xray.XrayConfigBuilder.buildSafeFallbackConfig(
            server(security = "reality", transport = "tcp", parameters = mapOf("fm" to "{\"tcp\":[]}", "pbk" to "public-key")),
        )).getJSONArray("outbounds").getJSONObject(0).getJSONObject("streamSettings")
        assertFalse(stream.has("finalmask"))
    }

    private fun server(
        parameters: Map<String, String> = emptyMap(),
        protocol: String = "vless",
        transport: String = "ws",
        security: String = "tls",
    ) = ServerRecord("server-1", "Test", "NL", protocol, "edge.example.com", 443,
        "private-credential", transport, security, parameters)
}

package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.subscription.ServerProfileOverrides
import dev.nirang.client.subscription.SubscriptionParser
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class XrayTlsCertificatePolicyTest {
    private val pin = "ab".repeat(32)
    private val base = "vless://test-id@edge.example.com:443?security=tls&type=ws"

    @Test fun `both certificate pin aliases emit normalized string and verification names`() {
        listOf("pcs", "pinSHA256").forEach { alias ->
            val server = SubscriptionParser.parse("$base&$alias=${"AB:".repeat(31)}AB&vcn=%20edge.example.com%20,%20FromMitM%20").single()
            val tls = tls(server)
            assertEquals(pin, tls.get("pinnedPeerCertSha256"))
            assertEquals("edge.example.com,FromMitM", tls.get("verifyPeerCertByName"))
            assertFalse(tls.has("allowInsecure"))
        }
    }

    @Test fun `pins normalize deduplicate and sort without losing profile persistence`() {
        val server = SubscriptionParser.parse("$base&pcs=${"cd".repeat(32)},$pin,$pin&pinSHA256=$pin,${"cd".repeat(32)}").single()
        val restored = ServerRecord.fromPrivateJson(server.toPrivateJson())
        val edited = ServerProfileOverrides().updated(restored, mapOf("sni" to "changed.example.com")).apply(listOf(restored)).single()
        assertEquals("$pin,${"cd".repeat(32)}", tls(edited).get("pinnedPeerCertSha256"))
    }

    @Test fun `malformed empty conflicting and repeated constraints cannot be concealed at import`() {
        listOf("pcs=", "pcs=sha256%2FAAAA%3D", "pcs=1234", "vcn=", "vcn=a,,b",
            "pcs=$pin&pcs=${"cd".repeat(32)}", "pcs=bad&pcs=$pin",
            "pcs=$pin&pinSHA256=${"cd".repeat(32)}", "vcn=a&vcn=b").forEach { query ->
            val result = SubscriptionParser.parseDetailed("$base&$query")
            assertEquals(query, 1, result.stats.failed)
            assertTrue(query, result.servers.isEmpty())
        }
    }

    @Test fun `equivalent repeated constraints remain accepted`() {
        val server = SubscriptionParser.parse("$base&pcs=$pin&pcs=${pin.uppercase()}&vcn=a,b&vcn=a,%20b").single()
        assertEquals(pin, tls(server).get("pinnedPeerCertSha256"))
        assertEquals("a,b", tls(server).get("verifyPeerCertByName"))
    }

    @Test fun `persisted invalid constraints and constraints outside TLS fail closed`() {
        val server = SubscriptionParser.parse(base).single()
        listOf(server.copy(parameters = mapOf("pcs" to "bad")),
            server.copy(security = "none", parameters = mapOf("pcs" to pin)),
            server.copy(security = "reality", parameters = mapOf("pbk" to "key", "vcn" to "a")),
            server.copy(security = "reality", parameters = mapOf("pbk" to "key", "fp" to "unsafe"))).forEach {
            assertThrows(IllegalArgumentException::class.java) { tls(it) }
        }
    }

    @Test fun `VMess certificate constraints survive JSON import`() {
        val payload = JSONObject().put("add", "edge.example.com").put("port", 443).put("id", "test-id")
            .put("net", "ws").put("tls", "tls").put("pinSHA256", pin).put("vcn", "edge.example.com")
        val server = SubscriptionParser.parse("vmess://" + Base64.getEncoder().encodeToString(payload.toString().toByteArray())).single()
        assertEquals(pin, tls(server).get("pinnedPeerCertSha256"))
        assertEquals("edge.example.com", tls(server).get("verifyPeerCertByName"))
    }

    private fun tls(server: ServerRecord): JSONObject = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
        .getJSONArray("outbounds").getJSONObject(0).getJSONObject("streamSettings").getJSONObject("tlsSettings")
}

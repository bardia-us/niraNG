package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ServerProfileOverridesTest {
    @Test
    fun `bundled core advanced fingerprints survive profile edits and reload`() {
        listOf("randomizednoalpn", "hellofirefox_148", "hellosafari_26_3", "hellochrome_120_pq", "hellogolang").forEach { fingerprint ->
            val source = server()
            val saved = ServerProfileOverrides().updated(source, mapOf("fp" to fingerprint))
            assertEquals(fingerprint, ServerProfileOverrides.fromJson(saved.toJson()).apply(listOf(source)).single().parameters["fp"])
        }
    }

    @Test
    fun `persisted edit reapplies after subscription reload preserving source credentials ids and order`() {
        val source = server(parameters = mapOf("host" to "cdn.example.com", "path" to "/ws", "fp" to "chrome"))
        val updated = ServerProfileOverrides().updated(source, mapOf("fp" to "unsafe", "fm" to "{\"tcp\":[]}"))
        val restored = ServerProfileOverrides.fromJson(updated.toJson())
        val freshSource = source.copy(parameters = source.parameters + ("path" to "/new-path"), pingMs = 17)
        val result = restored.apply(listOf(server(id = "another"), freshSource))
        assertEquals(listOf("another", "server-1"), result.map(ServerRecord::id))
        assertEquals("unsafe", result[1].parameters["fp"])
        assertEquals("{\"tcp\":[]}", result[1].parameters["fm"])
        assertEquals("/new-path", result[1].parameters["path"])
        assertEquals("private-credential", result[1].credential)
        assertEquals(17L, result[1].pingMs)
        assertEquals("chrome", source.parameters["fp"])
        assertFalse(updated.toJson().toString().contains("private-credential"))
    }

    @Test
    fun `clearing an override remains cleared after refresh and does not erase unrelated fields`() {
        val source = server(parameters = mapOf("fp" to "chrome", "fm" to "{\"tcp\":[]}", "cs" to "TLS_AES_128_GCM_SHA256"))
        val saved = ServerProfileOverrides().updated(source, mapOf("fm" to " ", "fp" to "Firefox"))
        val result = ServerProfileOverrides.fromJson(saved.toJson()).apply(listOf(source)).single()
        assertEquals("", result.parameters["fm"])
        assertEquals("firefox", result.parameters["fp"])
        assertEquals("TLS_AES_128_GCM_SHA256", result.parameters["cs"])
    }

    @Test
    fun `invalid input cannot overwrite an existing valid edit`() {
        val source = server()
        val saved = ServerProfileOverrides().updated(source, mapOf("fp" to "chrome"))
        listOf(
            mapOf("fm" to "[]"), mapOf("fm" to "{broken"), mapOf("fm" to "{} trailing"),
            mapOf("fp" to "invented"), mapOf("sni" to "https://example.com/path"),
            mapOf("alpn" to "h2,,http/1.1"), mapOf("cs" to "not_a_cipher"),
            mapOf("credential" to "new-secret"), mapOf("fp" to true),
        ).forEach { values ->
            assertThrows(IllegalArgumentException::class.java) { saved.updated(source, values) }
        }
        assertEquals("chrome", saved.apply(listOf(source)).single().parameters["fp"])
    }

    @Test
    fun `Reality rejects TLS-only options and unsafe fingerprint while preserving source options`() {
        val reality = server(security = "reality", transport = "tcp", parameters = mapOf("pbk" to "key", "cs" to "source-cipher"))
        listOf(mapOf("fp" to "unsafe"), mapOf("fm" to "{}"), mapOf("cs" to "TLS_AES_128_GCM_SHA256"), mapOf("alpn" to "h2"))
            .forEach { values -> assertThrows(IllegalArgumentException::class.java) { ServerProfileOverrides().updated(reality, values) } }
        val edited = ServerProfileOverrides().updated(reality, mapOf("sni" to "origin.example.com", "fp" to "firefox"))
            .apply(listOf(reality)).single()
        assertEquals("source-cipher", edited.parameters["cs"])
        assertEquals("key", edited.parameters["pbk"])
        assertEquals("origin.example.com", edited.parameters["sni"])
    }

    @Test
    fun `non-TLS and QUIC editor updates are rejected`() {
        listOf(server(security = "none"), server(protocol = "hysteria2", transport = "hysteria"))
            .forEach { assertThrows(IllegalArgumentException::class.java) { ServerProfileOverrides().updated(it, mapOf("fp" to "chrome")) } }
    }

    @Test
    fun `corrupt stored overrides are rejected without applying partial records`() {
        assertThrows(IllegalArgumentException::class.java) {
            ServerProfileOverrides.fromJson(JSONObject("{\"servers\":{\"server-1\":{\"credential\":\"secret\"}}}"))
        }
    }

    private fun server(
        id: String = "server-1", parameters: Map<String, String> = emptyMap(),
        protocol: String = "vless", transport: String = "ws", security: String = "tls",
    ) = ServerRecord(id, "Test", "NL", protocol, "edge.example.com", 443, "private-credential", transport, security, parameters)
}

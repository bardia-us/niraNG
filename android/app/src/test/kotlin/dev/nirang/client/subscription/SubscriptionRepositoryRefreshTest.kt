package dev.nirang.client.subscription

import dev.nirang.client.registration.RemoteSubscription
import dev.nirang.client.settings.MemoryPreferences
import java.io.File
import java.io.IOException
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SubscriptionRepositoryRefreshTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test
    fun `successful refresh restores every source field and clears edits across restart`() {
        val fixture = Fixture(temporary.newFolder())
        val repository = fixture.repository()
        repository.refresh()
        val original = repository.snapshot().servers.single()
        repository.updateServerProfile(original.id, manualEdits)
        assertEquals("firefox", repository.server(original.id)!!.parameters["fp"])

        val refreshed = repository.refresh().servers.single()
        assertEquals(original.parameters, refreshed.parameters)
        assertEquals(original.credential, refreshed.credential)
        assertEquals(original.parameters, fixture.repository().snapshot().servers.single().parameters)

        // A new edit belongs to the newly fetched subscription and still survives restart.
        repository.updateServerProfile(original.id, mapOf("fp" to "safari"))
        assertEquals("safari", fixture.repository().snapshot().servers.single().parameters["fp"])
    }

    @Test
    fun `fetch parse and persistence failures preserve cache overrides deletion order and selection`() {
        val fixture = Fixture(temporary.newFolder())
        val repository = fixture.repository()
        repository.refresh()
        val id = repository.snapshot().servers.single().id
        repository.updateServerProfile(id, manualEdits)
        repository.select(id)
        repository.reorder(listOf(id))
        repository.delete(id)
        val beforeSnapshot = repository.snapshot().toPrivateJson().toString()
        val beforeCache = File(fixture.directory, "subscription-cache.json").readText()
        val beforeOverrides = File(fixture.directory, "server-profile-overrides.json").readText()
        val beforePreferences = fixture.preferences.all.toMap()

        listOf("fetch", "parse", "persist").forEach { failure ->
            fixture.failure = failure
            assertThrows(IOException::class.java) { repository.refresh() }
            assertEquals(beforeSnapshot, repository.snapshot().toPrivateJson().toString())
            assertEquals(beforeCache, File(fixture.directory, "subscription-cache.json").readText())
            assertEquals(beforeOverrides, File(fixture.directory, "server-profile-overrides.json").readText())
            assertEquals(beforePreferences, fixture.preferences.all)
            assertEquals(beforeSnapshot, fixture.repository().snapshot().toPrivateJson().toString())
        }
    }

    @Test
    fun `refresh invalidates old override file using the same durable cache commit`() {
        val fixture = Fixture(temporary.newFolder())
        val repository = fixture.repository()
        repository.refresh()
        val original = repository.snapshot().servers.single()
        repository.updateServerProfile(original.id, manualEdits)
        val oldOverride = File(fixture.directory, "server-profile-overrides.json").readText()
        repository.refresh()

        // Simulate the old file surviving cleanup or being restored after the cache commit.
        File(fixture.directory, "server-profile-overrides.json").writeText(oldOverride)
        assertEquals(original.parameters, fixture.repository().snapshot().servers.single().parameters)
        repository.reorder(listOf(original.id))
        assertEquals(original.parameters, fixture.repository().snapshot().servers.single().parameters)
    }

    @Test
    fun `legacy overrides still load until the first successful refresh`() {
        val fixture = Fixture(temporary.newFolder())
        val source = SubscriptionParser.parse(SOURCE).single()
        val legacySnapshot = dev.nirang.client.model.SubscriptionSnapshot(
            listOf(source), dev.nirang.client.model.SubscriptionUsage(), 123L,
        )
        File(fixture.directory, "subscription-cache.json").writeText(legacySnapshot.toPrivateJson().toString())
        File(fixture.directory, "server-profile-overrides.json").writeText(
            ServerProfileOverrides().updated(source, manualEdits).toJson().toString(),
        )
        val repository = fixture.repository()
        assertEquals("firefox", repository.snapshot().servers.single().parameters["fp"])
        repository.refresh()
        assertEquals(source.parameters, fixture.repository().snapshot().servers.single().parameters)
    }

    @Test
    fun `existing bridge immediately reads source profiles after worker refresh`() {
        val (fixture, bridge, id) = editedBridge()
        fixture.repository().refresh()
        val original = SubscriptionParser.parse(SOURCE).single()
        assertEquals(original.parameters, bridge.selectedServer()!!.parameters)
        assertEquals(original.parameters, bridge.server(id)!!.parameters)
        assertEquals(original.parameters, bridge.snapshot().servers.single().parameters)
    }

    @Test
    fun `existing bridge ping write cannot revive edits after worker refresh`() {
        val (fixture, bridge, id) = editedBridge()
        fixture.repository().refresh()
        bridge.updatePing(id, 23L, "success")
        val restarted = fixture.repository().snapshot().servers.single()
        assertEquals(SubscriptionParser.parse(SOURCE).single().parameters, restarted.parameters)
        assertEquals(23L, restarted.pingMs)
    }

    @Test
    fun `existing bridge reorder cannot revive edits after worker refresh`() {
        val (fixture, bridge, id) = editedBridge()
        fixture.repository().refresh()
        assertTrue(bridge.reorder(listOf(id)))
        assertEquals(SubscriptionParser.parse(SOURCE).single().parameters,
            fixture.repository().snapshot().servers.single().parameters)
    }

    @Test
    fun `profile edit committed by another instance appears before the next read`() {
        val (fixture, bridge, id) = editedBridge()
        val worker = fixture.repository()
        worker.updateServerProfile(id, mapOf("fp" to "safari"))
        assertEquals("safari", bridge.selectedServer()!!.parameters["fp"])
        bridge.updateServerProfile(id, mapOf("sni" to "next.example.com"))
        assertEquals("safari", worker.server(id)!!.parameters["fp"])
        assertEquals("next.example.com", worker.server(id)!!.parameters["sni"])
    }

    @Test
    fun `failed worker writes do not invalidate or discard another instance edits`() {
        val (fixture, bridge, id) = editedBridge()
        val worker = fixture.repository()
        worker.snapshot()
        val reads = fixture.reads
        fixture.failure = "persist"
        assertThrows(IOException::class.java) { worker.refresh() }
        assertEquals("firefox", bridge.server(id)!!.parameters["fp"])
        assertEquals(reads, fixture.reads)
        assertThrows(IOException::class.java) { worker.updateServerProfile(id, mapOf("fp" to "safari")) }
        assertEquals("firefox", bridge.server(id)!!.parameters["fp"])
        assertEquals(reads, fixture.reads)
    }

    private fun editedBridge(): Triple<Fixture, SubscriptionRepository, String> {
        val fixture = Fixture(temporary.newFolder())
        val bridge = fixture.repository()
        val id = bridge.refresh().servers.single().id
        bridge.updateServerProfile(id, manualEdits)
        return Triple(fixture, bridge, id)
    }

    private class Fixture(val directory: File) {
        val preferences = MemoryPreferences()
        var failure: String? = null
        var reads = 0

        fun repository() = SubscriptionRepository(
            prefs = preferences,
            cacheDirectory = directory,
            fetchSubscription = {
                if (failure == "fetch") throw IOException("Synthetic fetch failure")
                val source = if (failure == "parse") "no usable server" else SOURCE
                RemoteSubscription(source.toByteArray(), "upload=1; download=2; total=100")
            },
            readCache = { reads++; SecureSubscriptionCache.Decoded(it.readText(), false) },
            writeCache = { file, text ->
                if (failure == "persist") throw IOException("Synthetic persistence failure")
                file.writeText(text)
            },
            log = { _, _ -> },
        )
    }

    private companion object {
        const val SOURCE = "vless://test-id@edge.example.com:443?security=tls&type=ws&path=%2Fsource&sni=origin.example.com&fp=chrome&alpn=h2&ech=AF7%2BDQBa%2FAAA%3D%3D"
        val manualEdits = mapOf(
            "sni" to "edited.example.com", "fp" to "firefox", "cs" to "TLS_AES_128_GCM_SHA256",
            "fm" to "{\"tcp\":[]}", "alpn" to "http/1.1", "echConfigList" to "h2c://1.1.1.1/dns-query",
            "echOutbound" to "{\"tag\":\"ech-dns\",\"protocol\":\"direct\",\"settings\":{\"redirect\":\"1.1.1.1:443\"}}",
        )
    }
}

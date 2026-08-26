package dev.nirang.client.subscription

import android.content.Context
import dev.nirang.client.BuildConfig
import dev.nirang.client.model.ServerRecord
import dev.nirang.client.model.SubscriptionSnapshot
import dev.nirang.client.model.SubscriptionUsage
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import javax.net.ssl.HttpsURLConnection

class SubscriptionRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences("nirang_subscription", Context.MODE_PRIVATE)
    private val cacheFile = File(context.noBackupFilesDir, "subscription-cache.json")

    @Volatile private var snapshot = SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
    @Volatile private var loaded = false

    fun snapshot(): SubscriptionSnapshot = synchronized(lock) {
        ensureLoaded()
        snapshot
    }

    fun selectedId(): String? = safeStringPreference("selectedServerId")

    fun visibleServerIds(): List<String> = synchronized(lock) {
        ensureLoaded()
        val hidden = hiddenIds()
        snapshot.servers.filterNot { it.id in hidden }.map(ServerRecord::id)
    }

    fun deletedCount(): Int = synchronized(lock) {
        ensureLoaded()
        val hidden = hiddenIds()
        snapshot.servers.count { it.id in hidden }
    }

    fun select(serverId: String): Boolean = synchronized(lock) {
        ensureLoaded()
        if (snapshot.servers.none { it.id == serverId } || serverId in hiddenIds()) return false
        prefs.edit().putString("selectedServerId", serverId).apply()
        true
    }

    fun selectedServer(): ServerRecord? = synchronized(lock) {
        ensureLoaded()
        val hidden = hiddenIds()
        val selected = selectedId()
        snapshot.servers.firstOrNull { it.id == selected && it.id !in hidden }
            ?: snapshot.servers.firstOrNull { it.id !in hidden }
    }

    fun server(serverId: String): ServerRecord? = synchronized(lock) {
        ensureLoaded()
        snapshot.servers.firstOrNull { it.id == serverId && it.id !in hiddenIds() }
    }

    fun safeServers(): List<Map<String, Any?>> = synchronized(lock) {
        ensureLoaded()
        val hidden = hiddenIds()
        val selected = selectedServer()?.id
        snapshot.servers.filterNot { it.id in hidden }.map { it.safeMetadata(selected) }
    }

    fun delete(serverId: String): Boolean = synchronized(lock) {
        ensureLoaded()
        if (snapshot.servers.none { it.id == serverId } || serverId in hiddenIds()) return false
        val updated = hiddenIds() + serverId
        prefs.edit().putStringSet(HIDDEN_SERVER_IDS, updated).apply()
        ensureVisibleSelection(updated)
        true
    }

    fun restoreDeleted(): Int = synchronized(lock) {
        ensureLoaded()
        val count = deletedCount()
        prefs.edit().remove(HIDDEN_SERVER_IDS).apply()
        ensureVisibleSelection(emptySet())
        count
    }

    fun updatePing(serverId: String, ping: Long?, status: String) = synchronized(lock) {
        ensureLoaded()
        snapshot.servers.firstOrNull { it.id == serverId }?.let {
            if (ping != null) it.pingMs = ping
            it.pingStatus = status
            if (status != "testing") runCatching { persist(snapshot) }
        }
    }

    @Throws(IOException::class)
    fun refresh(): SubscriptionSnapshot = synchronized(lock) {
        ensureLoaded()
        val endpoint = BuildConfig.SUBSCRIPTION_URL.trim()
        if (endpoint.isBlank()) throw IOException("Subscription endpoint is not configured")
        val url = URL(endpoint)
        if (url.protocol.lowercase() != "https") throw IOException("Subscription endpoint must use HTTPS")

        val connection = (url.openConnection() as HttpsURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 20_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "niraNG/1.0.7 Android")
            setRequestProperty("Accept", "text/plain, application/json")
            // A user-triggered refresh is an authoritative full sync. Sending
            // cache validators here made a valid 304 look like a failed update
            // and left locally hidden servers invisible indefinitely.
            useCaches = false
            setRequestProperty("Cache-Control", "no-cache")
        }

        try {
            val status = connection.responseCode
            if (status !in 200..299) throw IOException("Subscription request failed with HTTP $status")

            val bytes = connection.inputStream.use { it.readBytes() }
            if (bytes.size > MAX_SUBSCRIPTION_BYTES) throw IOException("Subscription response is too large")
            val servers = SubscriptionSyncPolicy.resetLatency(
                SubscriptionParser.parse(bytes.toString(Charsets.UTF_8)),
            )
            if (servers.isEmpty()) throw IOException("Subscription contains no supported servers")

            val usageHeader = connection.headerFields.entries
                .firstOrNull { it.key?.equals("subscription-userinfo", ignoreCase = true) == true }
                ?.value?.firstOrNull()
            val updated = SubscriptionSnapshot(
                servers = servers,
                usage = SubscriptionParser.parseUsage(usageHeader),
                lastUpdatedEpochMillis = System.currentTimeMillis(),
            )
            snapshot = updated
            persist(updated)
            // Delete is intentionally local and temporary. A successful full
            // sync restores every server still present in the subscription.
            prefs.edit().remove(HIDDEN_SERVER_IDS).apply()
            ensureVisibleSelection(emptySet())
            prefs.edit()
                .putString("etag", connection.getHeaderField("ETag"))
                .putString("lastModified", connection.getHeaderField("Last-Modified"))
                .apply()
            updated
        } finally {
            connection.disconnect()
        }
    }

    private fun loadFromDisk(): SubscriptionSnapshot {
        if (!cacheFile.exists()) return SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
        return runCatching {
            val json = JSONObject(cacheFile.readText())
            val array = json.getJSONArray("servers")
            val servers = (0 until array.length()).map { ServerRecord.fromPrivateJson(array.getJSONObject(it)) }
            SubscriptionSnapshot(
                servers = servers,
                usage = SubscriptionUsage.fromJson(json.optJSONObject("usage") ?: JSONObject()),
                lastUpdatedEpochMillis = json.optLong("lastUpdated"),
            )
        }.getOrElse {
            runCatching { cacheFile.delete() }
            SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
        }
    }

    private fun ensureLoaded() {
        if (loaded) return
        snapshot = loadFromDisk()
        loaded = true
    }

    private fun persist(value: SubscriptionSnapshot) {
        val temp = File(cacheFile.parentFile, "${cacheFile.name}.tmp")
        temp.writeText(value.toPrivateJson().toString())
        if (!temp.renameTo(cacheFile)) {
            cacheFile.writeText(temp.readText())
            temp.delete()
        }
    }

    private fun hiddenIds(): Set<String> = runCatching {
        prefs.getStringSet(HIDDEN_SERVER_IDS, emptySet())?.toSet().orEmpty()
    }.getOrElse {
        prefs.edit().remove(HIDDEN_SERVER_IDS).apply()
        emptySet()
    }

    private fun safeStringPreference(key: String): String? = runCatching { prefs.getString(key, null) }.getOrElse {
        prefs.edit().remove(key).apply()
        null
    }

    private fun ensureVisibleSelection(hidden: Set<String>) {
        val current = selectedId()
        if (current != null && snapshot.servers.any { it.id == current && it.id !in hidden }) return
        val firstVisible = snapshot.servers.firstOrNull { it.id !in hidden }?.id
        prefs.edit().run {
            if (firstVisible == null) remove("selectedServerId") else putString("selectedServerId", firstVisible)
        }.apply()
    }

    companion object {
        private const val HIDDEN_SERVER_IDS = "hiddenServerIds"
        private const val MAX_SUBSCRIPTION_BYTES = 4 * 1024 * 1024
        private val lock = Any()
    }
}

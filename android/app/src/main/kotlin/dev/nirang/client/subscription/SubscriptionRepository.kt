package dev.nirang.client.subscription

import android.content.Context
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ServerRecord
import dev.nirang.client.model.SubscriptionSnapshot
import dev.nirang.client.model.SubscriptionUsage
import dev.nirang.client.registration.DeviceRegistrationManager
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.IOException

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

    fun reorder(visibleIds: List<String>): Boolean = synchronized(lock) {
        ensureLoaded()
        val currentVisible = visibleServerIds()
        if (visibleIds.size != currentVisible.size || visibleIds.toSet() != currentVisible.toSet()) return false
        val hidden = hiddenIds()
        val completeOrder = visibleIds + snapshot.servers.filter { it.id in hidden }.map(ServerRecord::id)
        snapshot = snapshot.copy(servers = ServerOrderPolicy.apply(completeOrder, snapshot.servers))
        persist(snapshot)
        prefs.edit()
            .putString(SERVER_ORDER, JSONArray(snapshot.servers.map(ServerRecord::id).distinct()).toString())
            .putBoolean(SERVER_ORDER_MANUAL, true)
            .apply()
        true
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
        val remote = DeviceRegistrationManager.fetchSubscription(context)
        val bytes = remote.bytes
        if (bytes.size > MAX_SUBSCRIPTION_BYTES) throw IOException("Subscription response is too large")
        val parseResult = SubscriptionParser.parseDetailed(bytes.toString(Charsets.UTF_8))
        SafeLog.info(context, "Subscription parse ${parseResult.stats.summary()}")
        parseResult.failures.forEach { failure ->
            SafeLog.warning(context, "Subscription parser $failure")
        }
        if (parseResult.servers.isEmpty()) {
            throw IOException("Subscription contains no usable servers; existing servers were preserved")
        }
        val servers = SubscriptionSyncPolicy.resetLatency(
            SubscriptionSyncPolicy.reconcile(parseResult.servers),
        )
        if (!parseResult.stats.complete) {
            SafeLog.warning(context, "Subscription contained skipped entries; usable remote profiles replaced the cache")
        }

        val updated = SubscriptionSnapshot(
            servers = servers,
            usage = SubscriptionParser.parseUsage(remote.usageHeader),
            lastUpdatedEpochMillis = System.currentTimeMillis(),
        )
        persist(updated)
        snapshot = updated
        // A successful subscription refresh is authoritative: both temporary
        // latency sorting and persisted drag order return to the source order.
        prefs.edit()
            .remove(SERVER_ORDER)
            .remove(SERVER_ORDER_MANUAL)
            .apply()
        // Delete is intentionally local and temporary. A successful full
        // sync restores every server still present in the subscription.
        prefs.edit().remove(HIDDEN_SERVER_IDS).apply()
        ensureVisibleSelection(emptySet())
        updated
    }

    private fun loadFromDisk(): SubscriptionSnapshot {
        if (!cacheFile.exists()) return SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
        return runCatching {
            val decoded = SecureSubscriptionCache.read(cacheFile)
            val json = JSONObject(decoded.text)
            val array = json.getJSONArray("servers")
            val servers = (0 until array.length()).map { ServerRecord.fromPrivateJson(array.getJSONObject(it)) }
            val loadedSnapshot = SubscriptionSnapshot(
                servers = servers,
                usage = SubscriptionUsage.fromJson(json.optJSONObject("usage") ?: JSONObject()),
                lastUpdatedEpochMillis = json.optLong("lastUpdated"),
            )
            if (decoded.wasPlaintext) persist(loadedSnapshot)
            loadedSnapshot
        }.getOrElse {
            runCatching { cacheFile.delete() }
            SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
        }
    }

    private fun ensureLoaded() {
        if (loaded) return
        val loadedSnapshot = loadFromDisk()
        snapshot = if (prefs.getBoolean(SERVER_ORDER_MANUAL, false)) {
            loadedSnapshot.copy(servers = ServerOrderPolicy.apply(storedOrder(), loadedSnapshot.servers))
        } else {
            loadedSnapshot
        }
        loaded = true
    }

    private fun persist(value: SubscriptionSnapshot) {
        SecureSubscriptionCache.writeAtomic(cacheFile, value.toPrivateJson().toString())
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

    private fun storedOrder(): List<String> = runCatching {
        val array = JSONArray(prefs.getString(SERVER_ORDER, "[]") ?: "[]")
        (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }
    }.getOrElse {
        prefs.edit().remove(SERVER_ORDER).apply()
        emptyList()
    }

    private fun persistOrder(ids: List<String>) {
        prefs.edit().putString(SERVER_ORDER, JSONArray(ids.distinct()).toString()).apply()
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
        private const val SERVER_ORDER = "serverOrder"
        private const val SERVER_ORDER_MANUAL = "serverOrderManual"
        private const val MAX_SUBSCRIPTION_BYTES = 4 * 1024 * 1024
        private val lock = Any()
    }
}

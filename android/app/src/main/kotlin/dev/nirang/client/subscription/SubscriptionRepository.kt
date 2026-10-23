package dev.nirang.client.subscription

import android.content.Context
import android.content.SharedPreferences
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ServerRecord
import dev.nirang.client.model.SubscriptionSnapshot
import dev.nirang.client.model.SubscriptionUsage
import dev.nirang.client.registration.DeviceRegistrationManager
import dev.nirang.client.registration.RemoteSubscription
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.IOException
import java.util.UUID

class SubscriptionRepository internal constructor(
    private val prefs: SharedPreferences,
    cacheDirectory: File,
    private val fetchSubscription: () -> RemoteSubscription,
    private val readCache: (File) -> SecureSubscriptionCache.Decoded,
    private val writeCache: (File, String) -> Unit,
    private val log: (Boolean, String) -> Unit,
) {
    constructor(context: Context) : this(
        context.getSharedPreferences("nirang_subscription", Context.MODE_PRIVATE),
        context.noBackupFilesDir,
        { DeviceRegistrationManager.fetchSubscription(context) },
        SecureSubscriptionCache::read,
        SecureSubscriptionCache::writeAtomic,
        { warning, message -> if (warning) SafeLog.warning(context, message) else SafeLog.info(context, message) },
    )

    private val cacheFile = File(cacheDirectory, "subscription-cache.json")
    private val profileOverridesFile = File(cacheDirectory, "server-profile-overrides.json")
    private var profileOverrides = ServerProfileOverrides()
    private var profileOverrideRevision = ""

    @Volatile private var snapshot = SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
    @Volatile private var loaded = false
    private var observedGeneration = -1L

    fun snapshot(): SubscriptionSnapshot = synchronized(lock) {
        ensureLoaded()
        snapshot
    }

    fun selectedId(): String? = synchronized(lock) {
        ensureLoaded()
        safeStringPreference("selectedServerId")
    }

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

    fun updateServerProfile(serverId: String, values: Map<String, *>): Boolean = synchronized(lock) {
        ensureLoaded()
        val server = snapshot.servers.firstOrNull { it.id == serverId && it.id !in hiddenIds() }
            ?: return false
        val updated = profileOverrides.updated(server, values)
        // Write the encrypted override atomically before publishing it to readers.
        writeCache(profileOverridesFile, JSONObject()
            .put(PROFILE_OVERRIDE_REVISION, profileOverrideRevision)
            .put("overrides", updated.toJson()).toString())
        recordCommit()
        profileOverrides = updated
        snapshot = snapshot.copy(servers = updated.apply(snapshot.servers))
        true
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
        val candidate = snapshot.copy(servers = ServerOrderPolicy.apply(completeOrder, snapshot.servers))
        persist(candidate)
        snapshot = candidate
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
        val remote = fetchSubscription()
        val bytes = remote.bytes
        if (bytes.size > MAX_SUBSCRIPTION_BYTES) throw IOException("Subscription response is too large")
        val parseResult = SubscriptionParser.parseDetailed(bytes.toString(Charsets.UTF_8))
        log(false, "Subscription parse ${parseResult.stats.summary()}")
        parseResult.failures.forEach { failure ->
            log(true, "Subscription parser $failure")
        }
        if (parseResult.servers.isEmpty()) {
            throw IOException("Subscription contains no usable servers; existing servers were preserved")
        }
        val servers = SubscriptionSyncPolicy.resetLatency(
            SubscriptionSyncPolicy.reconcile(parseResult.servers),
        )
        if (!parseResult.stats.complete) {
            log(true, "Subscription contained skipped entries; usable remote profiles replaced the cache")
        }

        val updated = SubscriptionSnapshot(
            servers = servers,
            usage = SubscriptionParser.parseUsage(remote.usageHeader),
            lastUpdatedEpochMillis = System.currentTimeMillis(),
        )
        // One durable cache commit both publishes the source profiles and
        // invalidates old overrides. A separate delete/write could fail between
        // those operations and either lose edits on failure or revive them on restart.
        val revision = UUID.randomUUID().toString()
        persist(updated, revision)
        profileOverrideRevision = revision
        profileOverrides = ServerProfileOverrides()
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
            val decoded = readCache(cacheFile)
            val json = JSONObject(decoded.text)
            val array = json.getJSONArray("servers")
            val servers = (0 until array.length()).map { ServerRecord.fromPrivateJson(array.getJSONObject(it)) }
            val loadedSnapshot = SubscriptionSnapshot(
                servers = servers,
                usage = SubscriptionUsage.fromJson(json.optJSONObject("usage") ?: JSONObject()),
                lastUpdatedEpochMillis = json.optLong("lastUpdated"),
            )
            profileOverrideRevision = json.optString(PROFILE_OVERRIDE_REVISION)
            if (decoded.wasPlaintext) persist(loadedSnapshot)
            loadedSnapshot
        }.getOrElse {
            runCatching { cacheFile.delete() }
            SubscriptionSnapshot(emptyList(), SubscriptionUsage(), 0L)
        }
    }

    private fun ensureLoaded() {
        if (loaded && observedGeneration == commitGeneration) return
        val loadedSnapshot = loadFromDisk()
        profileOverrides = if (profileOverridesFile.exists()) runCatching {
            val json = JSONObject(readCache(profileOverridesFile).text)
            if (json.optString(PROFILE_OVERRIDE_REVISION) != profileOverrideRevision) {
                ServerProfileOverrides()
            } else {
                // Legacy cache/override pairs both have an empty revision.
                ServerProfileOverrides.fromJson(json.optJSONObject("overrides") ?: json)
            }
        }.getOrElse {
            log(true, "Stored profile overrides could not be read; source profiles were preserved")
            ServerProfileOverrides()
        } else ServerProfileOverrides()
        snapshot = if (prefs.getBoolean(SERVER_ORDER_MANUAL, false)) {
            loadedSnapshot.copy(servers = profileOverrides.apply(ServerOrderPolicy.apply(storedOrder(), loadedSnapshot.servers)))
        } else {
            loadedSnapshot.copy(servers = profileOverrides.apply(loadedSnapshot.servers))
        }
        loaded = true
        observedGeneration = commitGeneration
    }

    private fun persist(value: SubscriptionSnapshot, revision: String = profileOverrideRevision) {
        writeCache(cacheFile, value.toPrivateJson().put(PROFILE_OVERRIDE_REVISION, revision).toString())
        recordCommit()
    }

    // All callers hold the same process-wide lock. Publish invalidation only
    // after durable I/O, so a worker and the long-lived bridge cannot overwrite
    // one another using stale source profiles or stale profile edits.
    private fun recordCommit() {
        commitGeneration++
        observedGeneration = commitGeneration
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
        private const val PROFILE_OVERRIDE_REVISION = "profileOverrideRevision"
        private const val HIDDEN_SERVER_IDS = "hiddenServerIds"
        private const val SERVER_ORDER = "serverOrder"
        private const val SERVER_ORDER_MANUAL = "serverOrderManual"
        private const val MAX_SUBSCRIPTION_BYTES = 4 * 1024 * 1024
        private val lock = Any()
        private var commitGeneration = 0L
    }
}

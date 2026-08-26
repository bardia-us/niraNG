package dev.nirang.client.logs

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

object SafeLog {
    private const val MAX_ENTRIES = 250
    private const val MAX_STORED_CHARS = 512_000
    private val entries = ArrayDeque<LogEntry>()
    private val persistExecutor = Executors.newSingleThreadScheduledExecutor()
    private val persistScheduled = AtomicBoolean(false)
    @Volatile
    private var initialized = false

    @Synchronized
    fun initialize(context: Context) {
        if (initialized) return
        val prefs = context.getSharedPreferences("nirang_logs", Context.MODE_PRIVATE)
        val stored = runCatching { prefs.getString("entries", null) }.getOrElse {
            prefs.edit().remove("entries").apply()
            null
        }
        if (!stored.isNullOrBlank() && stored.length <= MAX_STORED_CHARS) {
            runCatching {
                val array = JSONArray(stored)
                val first = (array.length() - MAX_ENTRIES).coerceAtLeast(0)
                for (index in first until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val message = item.optString("message").take(1_200)
                    if (message.isBlank()) continue
                    val level = item.optString("level").takeIf { it in LEVELS } ?: "info"
                    entries.addLast(LogEntry(item.optLong("time"), level, message))
                }
            }.onFailure {
                entries.clear()
                prefs.edit().remove("entries").apply()
            }
        } else if (!stored.isNullOrBlank()) {
            prefs.edit().remove("entries").apply()
        }
        initialized = true
    }

    fun info(context: Context, message: String) = add(context, "info", message)
    fun warning(context: Context, message: String) = add(context, "warning", message)
    fun error(context: Context, message: String) = add(context, "error", message)

    @Synchronized
    fun add(context: Context, level: String, message: String) {
        initialize(context)
        entries.addLast(LogEntry(System.currentTimeMillis(), level.takeIf(LEVELS::contains) ?: "info", redact(message)))
        while (entries.size > MAX_ENTRIES) entries.removeFirst()
        schedulePersist(context.applicationContext)
    }

    @Synchronized
    fun list(context: Context): List<Map<String, Any>> {
        initialize(context)
        return entries.asReversed().map { mapOf("time" to it.time, "level" to it.level, "message" to it.message) }
    }

    @Synchronized
    fun clear(context: Context) {
        entries.clear()
        context.getSharedPreferences("nirang_logs", Context.MODE_PRIVATE)
            .edit().remove("entries").apply()
    }

    private fun schedulePersist(context: Context) {
        if (!persistScheduled.compareAndSet(false, true)) return
        persistExecutor.schedule({
            synchronized(this) {
                try {
                    persistNow(context)
                } finally {
                    persistScheduled.set(false)
                }
            }
        }, 250, TimeUnit.MILLISECONDS)
    }

    private fun persistNow(context: Context) {
        val array = JSONArray().apply {
            entries.forEach { entry ->
                put(JSONObject().apply {
                    put("time", entry.time)
                    put("level", entry.level)
                    put("message", entry.message)
                })
            }
        }
        context.getSharedPreferences("nirang_logs", Context.MODE_PRIVATE).edit()
            .putString("entries", array.toString()).apply()
    }

    private fun redact(input: String): String = input
        .replace(Regex("(?i)(vless|vmess|trojan)://\\S+"), "[redacted config]")
        .replace(Regex("https?://\\S+", RegexOption.IGNORE_CASE), "[redacted url]")
        .replace(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"), "[redacted id]")
        .replace(Regex("(?i)(password|credential|uuid|publicKey|shortId|id)\\s*[:=]\\s*[^,}\\s]+"), "$1=[redacted]")
        .replace(Regex("[A-Za-z0-9_+/-]{48,}={0,2}"), "[redacted value]")
        .take(1_200)

    private data class LogEntry(val time: Long, val level: String, val message: String)

    private val LEVELS = setOf("info", "warning", "error")
}

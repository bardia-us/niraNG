package dev.nirang.client.registration

import android.content.Context
import android.os.Build
import android.provider.Settings
import dev.nirang.client.BuildConfig
import dev.nirang.client.logs.SafeLog
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection

object DeviceRegistrationManager {
    private const val ENDPOINT = "https://neovip.ir/apiniraN/api.php"
    private const val CONSENT_VERSION = 1
    private const val SCHEMA_VERSION = 3
    private const val CONNECT_TIMEOUT_MS = 6_000
    private const val READ_TIMEOUT_MS = 8_000
    private const val MAX_RESPONSE_BYTES = 8_192
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nirang-device-registration").apply { isDaemon = true }
    }
    private val syncing = AtomicBoolean(false)

    fun hasConsent(context: Context): Boolean = runCatching {
        val prefs = preferences(context)
        prefs.getBoolean(CONSENT_ACCEPTED, false) &&
            prefs.getInt(CONSENT_VERSION_KEY, 0) == CONSENT_VERSION
    }.getOrDefault(false)

    fun accept(context: Context): Boolean {
        val prefs = preferences(context)
        val now = timestamp()
        val installationId = validInstallationId(prefs.getString(INSTALLATION_ID, null))
            ?: UUID.randomUUID().toString()
        val firstSeen = prefs.getString(FIRST_SEEN, null)?.takeIf(::isStoredTimestamp) ?: now
        val saved = prefs.edit()
            .putBoolean(CONSENT_ACCEPTED, true)
            .putInt(CONSENT_VERSION_KEY, CONSENT_VERSION)
            .putString(INSTALLATION_ID, installationId)
            .putString(FIRST_SEEN, firstSeen)
            .putString(LAST_SEEN, now)
            .commit()
        if (saved) scheduleSync(context)
        return saved
    }

    fun scheduleSync(context: Context) {
        if (!hasConsent(context) || !syncing.compareAndSet(false, true)) return
        val appContext = context.applicationContext
        executor.execute {
            try {
                sync(appContext)
            } catch (error: Throwable) {
                SafeLog.warning(appContext, "Device registration sync failed: ${error.javaClass.simpleName}")
            } finally {
                syncing.set(false)
            }
        }
    }

    internal fun payload(context: Context, now: String = timestamp()): JSONObject {
        val prefs = preferences(context)
        val installationId = validInstallationId(prefs.getString(INSTALLATION_ID, null))
            ?: error("Installation ID is unavailable")
        val manufacturer = clean(Build.MANUFACTURER, "Android")
        val model = clean(Build.MODEL, "Android device")
        val fallbackName = if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model"
        val deviceName = runCatching {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        }.getOrNull()?.let { clean(it, fallbackName) } ?: fallbackName
        val firstSeen = prefs.getString(FIRST_SEEN, null)?.takeIf(::isStoredTimestamp) ?: now
        return buildPayload(
            installationId = installationId,
            deviceName = deviceName,
            manufacturer = manufacturer,
            model = model,
            osVersion = clean("Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})", "Android"),
            appVersion = BuildConfig.VERSION_NAME,
            firstSeen = firstSeen,
            lastSeen = now,
        )
    }

    internal fun buildPayload(
        installationId: String,
        deviceName: String,
        manufacturer: String,
        model: String,
        osVersion: String,
        appVersion: String,
        firstSeen: String,
        lastSeen: String,
    ): JSONObject = JSONObject().apply {
        put("schema_version", SCHEMA_VERSION)
        put("platform", "android")
        put("installation_id", installationId)
        put("device_name", deviceName)
        put("manufacturer", manufacturer)
        put("model", model)
        put("os_version", osVersion)
        put("app_name", "niraNG")
        put("app_version", appVersion)
        put("first_seen", firstSeen)
        put("last_seen", lastSeen)
    }

    private fun sync(context: Context) {
        if (!hasConsent(context)) return
        val now = timestamp()
        val body = payload(context, now).toString().toByteArray(Charsets.UTF_8)
        val connection = (URL(ENDPOINT).openConnection() as HttpsURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = false
            doOutput = true
            setFixedLengthStreamingMode(body.size)
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "niraNG-device-registry/${BuildConfig.VERSION_NAME}")
        }
        try {
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val responseStream = if (status in 200..299) connection.inputStream else connection.errorStream
            val response = responseStream?.use { input -> input.readBounded(MAX_RESPONSE_BYTES + 1) } ?: ByteArray(0)
            require(response.size <= MAX_RESPONSE_BYTES) { "Registration response is too large" }
            val json = runCatching { JSONObject(response.toString(Charsets.UTF_8)) }.getOrNull()
            if (status !in 200..299) {
                val apiError = json?.optString("error")?.takeIf(SAFE_API_ERROR::matches) ?: "unknown"
                SafeLog.warning(context, "Device registration rejected: HTTP $status apiError=$apiError")
                error("Registration returned HTTP $status ($apiError)")
            }
            require(json?.optBoolean("ok") == true) {
                "Registration response is invalid"
            }
            preferences(context).edit().putString(LAST_SEEN, now).apply()
            SafeLog.info(context, "Device registration synchronized")
        } finally {
            connection.disconnect()
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences("nirang_installation", Context.MODE_PRIVATE)

    private fun validInstallationId(value: String?): String? = value?.takeIf {
        runCatching { UUID.fromString(it).version() == 4 }.getOrDefault(false)
    }

    private fun clean(value: String?, fallback: String): String {
        val normalized = value.orEmpty().replace(Regex("[\\u0000-\\u001f\\u007f]"), " ").trim()
        return (normalized.ifEmpty { fallback }).take(160)
    }

    private fun timestamp(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(Date())

    private fun isStoredTimestamp(value: String): Boolean =
        value.matches(Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z")) && runCatching {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                isLenient = false
                timeZone = TimeZone.getTimeZone("UTC")
            }.parse(value) != null
        }.getOrDefault(false)

    private fun InputStream.readBounded(limit: Int): ByteArray {
        val output = ByteArrayOutputStream(limit.coerceAtMost(1_024))
        val buffer = ByteArray(1_024)
        var remaining = limit
        while (remaining > 0) {
            val count = read(buffer, 0, minOf(buffer.size, remaining))
            if (count < 0) break
            output.write(buffer, 0, count)
            remaining -= count
        }
        return output.toByteArray()
    }

    private const val CONSENT_ACCEPTED = "deviceRegistrationConsentAccepted"
    private const val CONSENT_VERSION_KEY = "deviceRegistrationConsentVersion"
    private const val INSTALLATION_ID = "id"
    private const val FIRST_SEEN = "deviceRegistrationFirstSeen"
    private const val LAST_SEEN = "deviceRegistrationLastSeen"
    private val SAFE_API_ERROR = Regex("[a-z0-9_]{1,64}")
}

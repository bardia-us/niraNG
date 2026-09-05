package dev.nirang.client.registration

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import dev.nirang.client.BuildConfig
import dev.nirang.client.logs.SafeLog
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection

data class RemoteSubscription(val bytes: ByteArray, val usageHeader: String?)

class RemoteAccessException(val apiReason: String, message: String) : IOException(message)

object DeviceRegistrationManager {
    private const val ENDPOINT = "https://neovip.ir/apiniraN/api.php"
    private const val CONSENT_VERSION = 2
    private const val SCHEMA_VERSION = 6
    private const val CONNECT_TIMEOUT_MS = 6_000
    private const val READ_TIMEOUT_MS = 20_000
    private const val MAX_RESPONSE_BYTES = 4 * 1024 * 1024
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nirang-device-registration").apply { isDaemon = true }
    }
    private val syncing = AtomicBoolean(false)
    @Volatile private var lastAllowedElapsedRealtime = 0L

    fun hasConsent(context: Context): Boolean = runCatching {
        val prefs = preferences(context)
        prefs.getBoolean(CONSENT_ACCEPTED, false) && prefs.getInt(CONSENT_VERSION_KEY, 0) == CONSENT_VERSION
    }.getOrDefault(false)

    fun accept(context: Context): Boolean {
        val prefs = preferences(context)
        val now = timestamp()
        val installationId = validInstallationId(prefs.getString(INSTALLATION_ID, null)) ?: UUID.randomUUID().toString()
        val firstSeen = prefs.getString(FIRST_SEEN, null)?.takeIf(::isStoredTimestamp) ?: now
        val saved = prefs.edit()
            .putBoolean(CONSENT_ACCEPTED, true)
            .putInt(CONSENT_VERSION_KEY, CONSENT_VERSION)
            .putString(INSTALLATION_ID, installationId)
            .putString(FIRST_SEEN, firstSeen)
            .putString(LAST_SEEN, now)
            .commit()
        if (!saved) return false
        return true
    }

    fun scheduleSync(context: Context) {
        if (!hasConsent(context) || !syncing.compareAndSet(false, true)) return
        val appContext = context.applicationContext
        executor.execute {
            try {
                synchronize(appContext, register = accessToken(appContext) == null)
            } catch (error: Throwable) {
                SafeLog.warning(appContext, "Device access sync failed: ${error.javaClass.simpleName}")
            } finally {
                syncing.set(false)
            }
        }
    }

    fun runIfAllowed(context: Context, onAllowed: () -> Unit, onDenied: (Throwable) -> Unit) {
        if (isLocallyBlocked(context)) {
            onDenied(RemoteAccessException("blocked_by_administrator", "This device has been blocked by the administrator"))
        } else {
            onAllowed()
        }
    }

    fun isLocallyBlocked(context: Context): Boolean =
        preferences(context).getString(REMOTE_STATE, STATE_UNKNOWN) == STATE_BLOCKED

    @Throws(IOException::class)
    fun requireAllowed(context: Context) {
        check(hasConsent(context)) { "Device registration consent is required" }
        synchronize(context.applicationContext, register = accessToken(context) == null)
    }


    @Throws(IOException::class)
    fun fetchSubscription(context: Context): RemoteSubscription {
        check(hasConsent(context)) { "Device registration consent is required" }
        if (accessToken(context) == null) synchronize(context.applicationContext, register = true)
        var request = authorizedPayload(context, "subscription")
        var response = execute(context, request, accessToken(context), MAX_RESPONSE_BYTES)
        if (response.status == 401 && response.json?.optString("reason") in setOf("token_expired", "invalid_device_credentials")) {
            SecureTokenStore.clear(context)
            synchronize(context.applicationContext, register = true)
            request = authorizedPayload(context, "subscription")
            response = execute(context, request, accessToken(context), MAX_RESPONSE_BYTES)
        }
        if (response.status !in 200..299) handleDeniedResponse(context, response)
        require(response.bytes.isNotEmpty()) { "Subscription response is empty" }
        markAllowed(context)
        return RemoteSubscription(response.bytes, response.usageHeader)
    }

    internal fun payload(context: Context, now: String = timestamp()): JSONObject {
        val prefs = preferences(context)
        val installationId = validInstallationId(prefs.getString(INSTALLATION_ID, null))
            ?: error("Installation ID is unavailable")
        val manufacturer = clean(Build.MANUFACTURER, "Android")
        val model = clean(Build.MODEL, "Android device")
        val fallbackName = if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model"
        val deviceName = runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }
            .getOrNull()?.let { clean(it, fallbackName) } ?: fallbackName
        val firstSeen = prefs.getString(FIRST_SEEN, null)?.takeIf(::isStoredTimestamp) ?: now
        return buildPayload(
            installationId, deviceKey(context), deviceName, manufacturer, model,
            clean("Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})", "Android"),
            BuildConfig.VERSION_NAME, firstSeen, now,
        )
    }

    internal fun buildPayload(
        installationId: String,
        deviceKey: String,
        deviceName: String,
        manufacturer: String,
        model: String,
        osVersion: String,
        appVersion: String,
        firstSeen: String,
        lastSeen: String,
        requestTimestamp: Long = System.currentTimeMillis() / 1_000L,
        nonce: String = requestNonce(),
    ): JSONObject = JSONObject().apply {
        put("action", "register")
        put("schema_version", SCHEMA_VERSION)
        put("platform", "android")
        put("installation_id", installationId)
        put("device_key", deviceKey)
        put("device_name", deviceName)
        put("manufacturer", manufacturer)
        put("model", model)
        put("os_version", osVersion)
        put("app_name", "niraNG")
        put("app_version", appVersion)
        put("first_seen", firstSeen)
        put("last_seen", lastSeen)
        put("request_timestamp", requestTimestamp)
        put("request_nonce", nonce)
    }

    internal fun deriveDeviceKey(androidId: String, packageName: String = "dev.nirang.client"): String {
        val normalized = androidId.trim().lowercase(Locale.US)
        require(normalized.matches(Regex("[0-9a-f]{16}")) && normalized != "9774d56d682e549c") {
            "ANDROID_ID is unavailable"
        }
        return MessageDigest.getInstance("SHA-256")
            .digest("niraNG-device-key-v1\u0000$packageName\u0000$normalized".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    private fun deviceKey(context: Context): String {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: throw RemoteAccessException("device_identity_unavailable", "Android device identity is unavailable")
        return deriveDeviceKey(androidId, context.packageName)
    }

    private fun synchronize(context: Context, register: Boolean) = synchronized(accessLock) {
        val request = if (register) payload(context) else authorizedPayload(context, "status")
        val response = execute(context, request, if (register) null else accessToken(context), 8_192)
        val json = response.json
        if (response.status !in 200..299 || json?.optBoolean("allowed") != true) {
            handleDeniedResponse(context, response)
        }
        val editor = preferences(context).edit().putString(REMOTE_STATE, STATE_ALLOWED).putString(LAST_SEEN, timestamp())
        if (register) {
            val token = json.optString("access_token")
            require(token.matches(Regex("[A-Za-z0-9_-]{43}"))) { "Registration token is invalid" }
            val expiresInSeconds = json.optLong("expires_in", DEFAULT_TOKEN_LIFETIME_SECONDS)
                .coerceIn(60L, MAX_TOKEN_LIFETIME_SECONDS)
            SecureTokenStore.put(context, token, System.currentTimeMillis() + expiresInSeconds * 1_000L)
        }
        editor.apply()
        lastAllowedElapsedRealtime = SystemClock.elapsedRealtime()
        SafeLog.info(context, "Device access synchronized")
    }

    private fun authorizedPayload(context: Context, action: String): JSONObject {
        val prefs = preferences(context)
        return JSONObject().apply {
            put("action", action)
            put("schema_version", SCHEMA_VERSION)
            put("installation_id", validInstallationId(prefs.getString(INSTALLATION_ID, null)) ?: error("Installation ID is unavailable"))
            put("device_key", deviceKey(context))
            put("app_version", BuildConfig.VERSION_NAME)
            put("request_timestamp", System.currentTimeMillis() / 1_000L)
            put("request_nonce", requestNonce())
        }
    }

    private fun execute(context: Context, payload: JSONObject, token: String?, maxBytes: Int): ApiResponse {
        val body = payload.toString().toByteArray(Charsets.UTF_8)
        val connection = (URL(ENDPOINT).openConnection() as HttpsURLConnection).apply {
            sslSocketFactory = ApiPinning.socketFactory
            requestMethod = "POST"
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = false
            doOutput = true
            setFixedLengthStreamingMode(body.size)
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json, text/plain")
            setRequestProperty("User-Agent", "niraNG-device-access/${BuildConfig.VERSION_NAME}")
            if (token != null) setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val bytes = stream?.use { it.readBounded(maxBytes + 1) } ?: ByteArray(0)
            require(bytes.size <= maxBytes) { "API response is too large" }
            val json = if (connection.contentType.orEmpty().contains("json", ignoreCase = true) || status !in 200..299) {
                runCatching { JSONObject(bytes.toString(Charsets.UTF_8)) }.getOrNull()
            } else null
            return ApiResponse(status, bytes, json, connection.getHeaderField("subscription-userinfo"))
        } finally {
            connection.disconnect()
        }
    }

    private fun handleDeniedResponse(context: Context, response: ApiResponse): Nothing {
        lastAllowedElapsedRealtime = 0L
        val json = response.json
        val reason = json?.optString("reason")?.takeIf(SAFE_API_ERROR::matches)
            ?: json?.optString("error")?.takeIf(SAFE_API_ERROR::matches) ?: "access_denied"
        val state = when {
            json?.optBoolean("blocked") == true || response.status == 403 -> STATE_BLOCKED
            json?.optBoolean("update_required") == true || response.status == 426 -> STATE_OUTDATED
            else -> STATE_UNKNOWN
        }
        val editor = preferences(context).edit().putString(REMOTE_STATE, state)
        editor.apply()
        val message = when (state) {
            STATE_BLOCKED -> "This device has been blocked by the administrator"
            STATE_OUTDATED -> "niraNG must be updated to ${json?.optString("minimum_version").orEmpty()}"
            else -> "Device access could not be verified"
        }
        SafeLog.warning(context, "Remote access denied: HTTP ${response.status} reason=$reason")
        throw RemoteAccessException(reason, message)
    }

    private fun markAllowed(context: Context) {
        preferences(context).edit().putString(REMOTE_STATE, STATE_ALLOWED).putString(LAST_SEEN, timestamp()).apply()
        lastAllowedElapsedRealtime = SystemClock.elapsedRealtime()
    }

    private fun accessToken(context: Context): String? = SecureTokenStore.get(context)
        ?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{43}")) }
    private fun requestNonce(): String {
        val bytes = ByteArray(16).also(SecureRandom()::nextBytes)
        return android.util.Base64.encodeToString(
            bytes,
            android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING,
        )
    }
    private fun preferences(context: Context) = context.getSharedPreferences("nirang_installation", Context.MODE_PRIVATE)
    private fun validInstallationId(value: String?): String? = value?.takeIf { runCatching { UUID.fromString(it).version() == 4 }.getOrDefault(false) }
    private fun clean(value: String?, fallback: String): String = value.orEmpty().replace(Regex("[\\u0000-\\u001f\\u007f]"), " ").trim().ifEmpty { fallback }.take(160)
    private fun timestamp(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
    private fun isStoredTimestamp(value: String): Boolean = value.matches(Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z"))
    private fun InputStream.readBounded(limit: Int): ByteArray {
        val output = ByteArrayOutputStream(limit.coerceAtMost(1_024)); val buffer = ByteArray(1_024); var remaining = limit
        while (remaining > 0) { val count = read(buffer, 0, minOf(buffer.size, remaining)); if (count < 0) break; output.write(buffer, 0, count); remaining -= count }
        return output.toByteArray()
    }

    private data class ApiResponse(val status: Int, val bytes: ByteArray, val json: JSONObject?, val usageHeader: String?)
    private const val CONSENT_ACCEPTED = "deviceRegistrationConsentAccepted"
    private const val CONSENT_VERSION_KEY = "deviceRegistrationConsentVersion"
    private const val INSTALLATION_ID = "id"
    private const val FIRST_SEEN = "deviceRegistrationFirstSeen"
    private const val LAST_SEEN = "deviceRegistrationLastSeen"
    private const val REMOTE_STATE = "remoteAccessState"
    private const val STATE_ALLOWED = "allowed"
    private const val STATE_BLOCKED = "blocked"
    private const val STATE_OUTDATED = "outdated"
    private const val STATE_UNKNOWN = "unknown"
    private val accessLock = Any()
    private val SAFE_API_ERROR = Regex("[a-z0-9_]{1,64}")
    private const val DEFAULT_TOKEN_LIFETIME_SECONDS = 86_400L
    private const val MAX_TOKEN_LIFETIME_SECONDS = 7L * 86_400L
}

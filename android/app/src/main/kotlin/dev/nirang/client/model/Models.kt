package dev.nirang.client.model

import org.json.JSONArray
import org.json.JSONObject

enum class ConnectionState(val wireValue: String) {
    DISCONNECTED("disconnected"),
    PREPARING("preparing"),
    CONNECTING("connecting"),
    CONNECTED("connected"),
    RESTARTING("restarting"),
    SWITCHING("switching"),
    RECONNECTING("reconnecting"),
    STOPPING("stopping"),
    ERROR("error"),
}

data class ServerRecord(
    val id: String,
    val name: String,
    val country: String,
    val protocol: String,
    val address: String,
    val port: Int,
    val credential: String,
    val transport: String,
    val security: String,
    val parameters: Map<String, String>,
    var pingMs: Long? = null,
    var pingStatus: String = "idle",
) {
    fun safeMetadata(selectedId: String?): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "country" to country,
        "protocol" to protocol.uppercase(),
        "transport" to transportLabel(),
        "security" to securityLabel(),
        "port" to port,
        "sni" to parameters["sni"].orEmpty(),
        "credentialLabel" to if (protocol.lowercase() in setOf("vless", "vmess")) "UUID" else "Password",
        "credentialMasked" to if (protocol.lowercase() in setOf("vless", "vmess")) "********-****-****-****-************" else "••••••••••••",
        "realityPublicKeyMasked" to if (parameters["pbk"].isNullOrBlank()) "" else "••••••••••••••••",
        "shortIdMasked" to if (parameters["sid"].isNullOrBlank()) "" else "••••••",
        "ping" to pingMs,
        "selected" to (id == selectedId),
        "status" to pingStatus,
    )

    fun toPrivateJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("country", country)
        put("protocol", protocol)
        put("address", address)
        put("port", port)
        put("credential", credential)
        put("transport", transport)
        put("security", security)
        put("parameters", JSONObject(parameters))
        put("pingMs", pingMs ?: JSONObject.NULL)
        put("pingStatus", pingStatus)
    }

    private fun transportLabel(): String {
        val transportName = when (transport.lowercase()) {
            "ws" -> "WebSocket"
            "grpc" -> "gRPC"
            "xhttp", "splithttp" -> "XHTTP"
            "hysteria" -> "Hysteria/QUIC"
            else -> transport.uppercase()
        }
        return transportName
    }

    private fun securityLabel(): String = when (security.lowercase()) {
        "reality" -> "Reality"
        "tls" -> "TLS"
        "none", "" -> "None"
        else -> security.uppercase()
    }

    companion object {
        fun fromPrivateJson(json: JSONObject): ServerRecord {
            val paramsJson = json.optJSONObject("parameters") ?: JSONObject()
            val params = buildMap {
                paramsJson.keys().forEach { key -> put(key, paramsJson.optString(key)) }
            }
            return ServerRecord(
                id = json.getString("id"),
                name = json.getString("name"),
                country = json.optString("country"),
                protocol = json.getString("protocol"),
                address = json.getString("address"),
                port = json.getInt("port"),
                credential = json.getString("credential"),
                transport = json.optString("transport", "tcp"),
                security = json.optString("security", "none"),
                parameters = params,
                pingMs = if (json.isNull("pingMs")) null else json.optLong("pingMs"),
                pingStatus = json.optString("pingStatus", "idle"),
            )
        }
    }
}

data class SubscriptionUsage(
    val upload: Long? = null,
    val download: Long? = null,
    val total: Long? = null,
    val expireEpochSeconds: Long? = null,
) {
    val used: Long? get() = if (upload != null || download != null) (upload ?: 0L) + (download ?: 0L) else null
    val remaining: Long? get() = if (total != null && total > 0 && used != null) (total - used!!).coerceAtLeast(0L) else null
    val isUnlimited: Boolean get() = total == 0L
    val isExpired: Boolean get() = expireEpochSeconds?.let { it > 0 && it * 1000L < System.currentTimeMillis() } ?: false

    fun toMap(): Map<String, Any?> = mapOf(
        "upload" to upload,
        "download" to download,
        "used" to used,
        "total" to total,
        "remaining" to remaining,
        "expire" to expireEpochSeconds,
        "unlimited" to isUnlimited,
        "expired" to isExpired,
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("upload", upload ?: JSONObject.NULL)
        put("download", download ?: JSONObject.NULL)
        put("total", total ?: JSONObject.NULL)
        put("expire", expireEpochSeconds ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(json: JSONObject): SubscriptionUsage = SubscriptionUsage(
            upload = json.optNullableLong("upload"),
            download = json.optNullableLong("download"),
            total = json.optNullableLong("total"),
            expireEpochSeconds = json.optNullableLong("expire"),
        )
    }
}

data class SubscriptionSnapshot(
    val servers: List<ServerRecord>,
    val usage: SubscriptionUsage,
    val lastUpdatedEpochMillis: Long,
) {
    fun toPrivateJson(): JSONObject = JSONObject().apply {
        put("servers", JSONArray().apply { servers.forEach { put(it.toPrivateJson()) } })
        put("usage", usage.toJson())
        put("lastUpdated", lastUpdatedEpochMillis)
    }
}

private fun JSONObject.optNullableLong(key: String): Long? =
    if (!has(key) || isNull(key)) null else optLong(key)

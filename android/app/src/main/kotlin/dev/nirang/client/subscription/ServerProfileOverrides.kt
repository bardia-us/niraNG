package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import org.json.JSONObject
import org.json.JSONTokener
import java.net.IDN

class ServerProfileOverrides private constructor(private val records: Map<String, Map<String, String>>) {
    constructor() : this(emptyMap())

    fun updated(server: ServerRecord, values: Map<String, *>): ServerProfileOverrides {
        require(server.profileEditable) { "This profile does not support TLS edits" }
        require(values.isNotEmpty()) { "No profile values supplied" }
        val normalized = values.mapValues { (key, value) -> normalize(key, value, server.security.equals("reality", true)) }
        return ServerProfileOverrides(records + (server.id to (records[server.id].orEmpty() + normalized)))
    }

    fun apply(servers: List<ServerRecord>): List<ServerRecord> = servers.map { server ->
        val values = records[server.id]
        if (values == null || !server.profileEditable) server
        else server.copy(parameters = server.parameters + values)
    }

    fun toJson(): JSONObject = JSONObject().put("servers", JSONObject().apply {
        records.forEach { (id, values) -> put(id, JSONObject(values)) }
    })

    companion object {
        private val fingerprints = setOf("chrome", "firefox", "safari", "ios", "android", "edge", "360", "qq", "random", "randomized", "unsafe")
        private val tlsOnly = setOf("cs", "fm", "alpn")

        fun fromJson(value: JSONObject): ServerProfileOverrides {
            require(value.length() == 1 && value.has("servers")) { "Invalid profile overrides" }
            val servers = value.getJSONObject("servers")
            val records = buildMap {
                servers.keys().forEach { id ->
                    require(id.isNotBlank()) { "Invalid profile identifier" }
                    val record = servers.getJSONObject(id)
                    put(id, buildMap {
                        record.keys().forEach { key -> put(key, normalize(key, record.get(key), false)) }
                    })
                }
            }
            return ServerProfileOverrides(records)
        }

        private fun normalize(key: String, raw: Any?, reality: Boolean): String {
            require(key in setOf("sni", "fp", "cs", "fm", "alpn") && raw is String) { "Invalid profile option" }
            require(!reality || key !in tlsOnly) { "This option requires TLS" }
            val value = raw.trim()
            require(value.length <= if (key == "fm") 32768 else 4096) { "Profile option is too long" }
            if (value.isEmpty()) return ""
            return when (key) {
                "fp" -> value.lowercase().also {
                    require(it in fingerprints && (!reality || it != "unsafe")) { "Unsupported fingerprint" }
                }
                "sni" -> {
                    val ascii = runCatching { IDN.toASCII(value) }.getOrElse { throw IllegalArgumentException("Invalid SNI", it) }
                    require(ascii.length <= 253 && ascii.trimEnd('.').split('.').all {
                        it.isNotEmpty() && it.length <= 63 && it.first().isLetterOrDigit() &&
                            it.last().isLetterOrDigit() && it.all { character -> character.isLetterOrDigit() || character == '-' }
                    }) { "Invalid SNI" }
                    value
                }
                "alpn" -> {
                    val protocols = value.split(',').map(String::trim)
                    require(protocols.all { it.isNotEmpty() && it.toByteArray(Charsets.UTF_8).size <= 255 && it.all { c -> c.code in 33..126 } }) { "Invalid ALPN" }
                    protocols.joinToString(",")
                }
                "cs" -> {
                    val ciphers = value.split(':').map(String::trim)
                    require(ciphers.all { it in cipherSuites }) { "Unsupported cipher suite" }
                    ciphers.joinToString(":")
                }
                "fm" -> {
                    val tokener = JSONTokener(value)
                    val json = runCatching { tokener.nextValue() }.getOrElse { throw IllegalArgumentException("Invalid FinalMask JSON", it) }
                    require(json is JSONObject && tokener.nextClean() == '\u0000') { "FinalMask must be a JSON object" }
                    value
                }
                else -> error("Invalid profile option")
            }
        }

        private val cipherSuites = setOf(
            "TLS_AES_128_GCM_SHA256", "TLS_AES_256_GCM_SHA384", "TLS_CHACHA20_POLY1305_SHA256",
            "TLS_RSA_WITH_RC4_128_SHA", "TLS_RSA_WITH_3DES_EDE_CBC_SHA", "TLS_RSA_WITH_AES_128_CBC_SHA",
            "TLS_RSA_WITH_AES_256_CBC_SHA", "TLS_RSA_WITH_AES_128_CBC_SHA256", "TLS_RSA_WITH_AES_128_GCM_SHA256",
            "TLS_RSA_WITH_AES_256_GCM_SHA384", "TLS_ECDHE_ECDSA_WITH_RC4_128_SHA", "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
            "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA", "TLS_ECDHE_RSA_WITH_RC4_128_SHA", "TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA",
            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA", "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA", "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256", "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384", "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
            "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256", "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
        )
    }
}

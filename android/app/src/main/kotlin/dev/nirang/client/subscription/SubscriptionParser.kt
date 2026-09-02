package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.model.SubscriptionUsage
import org.json.JSONObject
import java.net.IDN
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64

data class SubscriptionParseStats(val total: Int, val parsed: Int, val skipped: Int, val failed: Int, val duplicates: Int) {
    val complete: Boolean get() = parsed > 0 && skipped == 0 && failed == 0
    fun summary() = "total=$total parsed=$parsed skipped=$skipped failed=$failed duplicates=$duplicates"
}
data class SubscriptionParseResult(val servers: List<ServerRecord>, val stats: SubscriptionParseStats, val failures: List<String>)

object SubscriptionParser {
    fun parse(body: String): List<ServerRecord> = parseDetailed(body).servers

    fun parseDetailed(body: String): SubscriptionParseResult {
        val normalized = body.trim().removePrefix("\uFEFF")
        val content = if (normalized.contains("://")) normalized else decodeBase64(normalized) ?: normalized
        val records = linkedMapOf<String, ServerRecord>()
        val failures = mutableListOf<String>()
        var total = 0; var parsed = 0; var skipped = 0; var failed = 0; var duplicates = 0
        content.lineSequence().map(String::trim).filter { it.isNotEmpty() && !it.startsWith("#") }
            .forEachIndexed { index, line ->
                total++
                val scheme = line.substringBefore("://", "unknown").lowercase().take(16)
                val recognized = scheme in RECOGNIZED_SCHEMES
                val record = runCatching {
                    when (scheme) {
                        "vless", "trojan" -> parseStandardUri(line, scheme)
                        "vmess" -> parseVmess(line)
                        "ss" -> parseShadowsocks(line)
                        "socks", "socks5" -> parseUserPasswordProxy(line, "socks")
                        "http", "https" -> parseUserPasswordProxy(line, "http")
                        "hy2", "hysteria2" -> parseHysteria2(line)
                        "hysteria" -> null // This Core's Hysteria outbound requires version 2.
                        else -> null
                    }
                }.onFailure { error ->
                    failed++
                    failures += "entry=${index + 1} protocol=$scheme error=${error.javaClass.simpleName}"
                }.getOrNull()
                if (record == null) {
                    if (!recognized || scheme == "hysteria") skipped++
                    return@forEachIndexed
                }
                parsed++
                if (records.putIfAbsent(record.id, record) != null) duplicates++
            }
        return SubscriptionParseResult(records.values.toList(), SubscriptionParseStats(total, parsed, skipped, failed, duplicates), failures.take(8))
    }

    fun parseUsage(header: String?): SubscriptionUsage {
        if (header.isNullOrBlank()) return SubscriptionUsage()
        val values = header.split(';').mapNotNull { field ->
            val parts = field.trim().split('=', limit = 2)
            if (parts.size == 2) parts[0].lowercase() to parts[1].trim().toLongOrNull() else null
        }.toMap()
        return SubscriptionUsage(values["upload"], values["download"], values["total"], values["expire"])
    }

    private fun parseStandardUri(raw: String, protocol: String): ServerRecord {
        val uri = URI(raw)
        val query = parseQuery(uri.rawQuery)
        val credential = decode(uri.rawUserInfo ?: error("Missing credential"))
        val host = normalizedHost(uri.host ?: error("Missing host"))
        val port = uri.port.takeIf { it > 0 } ?: if (query["security"] in setOf("tls", "reality")) 443 else 80
        val name = decode(uri.rawFragment ?: "Server").ifBlank { "Server" }
        return server(name, protocol, host, port, credential, query["type"]?.ifBlank { "tcp" } ?: "tcp", query["security"]?.ifBlank { "none" } ?: "none", query)
    }

    private fun parseVmess(raw: String): ServerRecord {
        val json = JSONObject(decodeBase64(raw.substringAfter("vmess://")) ?: error("Invalid VMess payload"))
        val parameters = buildMap {
            mapOf("alterId" to "aid", "encryption" to "scy", "host" to "host", "path" to "path", "sni" to "sni", "alpn" to "alpn", "fp" to "fp", "flow" to "flow", "headerType" to "type")
                .forEach { (target, source) -> json.optString(source).takeIf(String::isNotBlank)?.let { put(target, it) } }
        }
        return server(json.optString("ps", "Server").ifBlank { "Server" }, "vmess", normalizedHost(json.getString("add")), json.optString("port").toIntOrNull() ?: json.optInt("port", 443), json.getString("id"), json.optString("net", "tcp"), json.optString("tls", "none").ifBlank { "none" }, parameters)
    }

    private fun parseShadowsocks(raw: String): ServerRecord {
        val encoded = raw.substringAfter("://")
        val fragmentIndex = encoded.indexOf('#')
        val fragment = if (fragmentIndex >= 0) encoded.substring(fragmentIndex + 1) else "Server"
        val beforeFragment = if (fragmentIndex >= 0) encoded.substring(0, fragmentIndex) else encoded
        val queryIndex = beforeFragment.indexOf('?')
        val authority = if (queryIndex >= 0) beforeFragment.substring(0, queryIndex) else beforeFragment
        val query = parseQuery(if (queryIndex >= 0) beforeFragment.substring(queryIndex + 1) else null)
        require(query["plugin"].isNullOrBlank()) { "Shadowsocks plugins are not bundled" }
        val decodedAuthority = if ('@' in authority) authority else decodeBase64(authority) ?: error("Invalid Shadowsocks payload")
        val at = decodedAuthority.lastIndexOf('@')
        require(at > 0) { "Missing Shadowsocks server" }
        val encodedUser = decodedAuthority.substring(0, at)
        val user = decodeBase64(encodedUser) ?: decode(encodedUser)
        val separator = user.indexOf(':')
        require(separator > 0) { "Missing Shadowsocks method or password" }
        val method = user.substring(0, separator).lowercase()
        require(method in SHADOWSOCKS_METHODS) { "Unsupported Shadowsocks method" }
        val password = user.substring(separator + 1)
        require(password.isNotEmpty()) { "Missing Shadowsocks password" }
        val (host, port) = parseHostPort(decodedAuthority.substring(at + 1))
        return server(decode(fragment).ifBlank { "Server" }, "shadowsocks", host, port, password, "tcp", "none", query + ("method" to method))
    }

    private fun parseUserPasswordProxy(raw: String, protocol: String): ServerRecord {
        val uri = URI(raw)
        require(uri.port > 0) { "Missing proxy port" }
        val encodedUser = uri.rawUserInfo.orEmpty()
        val user = decodeBase64(encodedUser) ?: decode(encodedUser)
        val separator = user.indexOf(':')
        val username = if (separator >= 0) user.substring(0, separator) else user
        val password = if (separator >= 0) user.substring(separator + 1) else ""
        val parameters = parseQuery(uri.rawQuery).toMutableMap().apply { if (username.isNotEmpty()) put("username", username) }
        return server(decode(uri.rawFragment ?: "Server").ifBlank { "Server" }, protocol, normalizedHost(uri.host ?: error("Missing host")), uri.port, password, "tcp", if (raw.startsWith("https://", true)) "tls" else "none", parameters)
    }

    private fun parseHysteria2(raw: String): ServerRecord {
        val uri = URI(raw)
        val query = parseQuery(uri.rawQuery)
        require(query["mport"].isNullOrBlank()) { "Hysteria2 port hopping is not supported" }
        val obfs = query["obfs"]?.lowercase()
        if (!obfs.isNullOrBlank()) require(obfs == "salamander" && !query["obfs-password"].isNullOrBlank()) { "Unsupported Hysteria2 obfuscation" }
        return server(decode(uri.rawFragment ?: "Server").ifBlank { "Server" }, "hysteria2", normalizedHost(uri.host ?: error("Missing host")), uri.port.takeIf { it > 0 } ?: 443, decode(uri.rawUserInfo ?: error("Missing Hysteria2 authentication")), "hysteria", "tls", query + ("version" to "2"))
    }

    private fun server(name: String, protocol: String, address: String, port: Int, credential: String, transport: String, security: String, parameters: Map<String, String>) = ServerRecord(
        id = stableId(protocol, address, port, credential, transport, security, parameters), name = name, country = inferCountry(name), protocol = protocol, address = address, port = port, credential = credential, transport = transport, security = security, parameters = parameters,
    )

    private fun parseHostPort(value: String): Pair<String, Int> {
        val uri = URI("ss://$value")
        require(uri.port > 0) { "Missing Shadowsocks port" }
        return normalizedHost(uri.host ?: error("Missing host")) to uri.port
    }

    private fun parseQuery(raw: String?): Map<String, String> = if (raw.isNullOrBlank()) emptyMap() else raw.split('&').associate { part ->
        val pieces = part.split('=', limit = 2); decode(pieces[0]) to decode(pieces.getOrElse(1) { "" })
    }

    private fun decodeBase64(input: String): String? {
        if (input.isBlank()) return null
        val compact = input.filterNot(Char::isWhitespace)
        val padded = compact + "=".repeat((4 - compact.length % 4) % 4)
        return listOf(Base64.getUrlDecoder(), Base64.getDecoder()).firstNotNullOfOrNull { decoder -> runCatching { String(decoder.decode(padded), StandardCharsets.UTF_8) }.getOrNull() }
    }

    private fun decode(value: String) = URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8.name())
    private fun normalizedHost(value: String) = runCatching { IDN.toASCII(value.trim().trim('[', ']')) }.getOrElse { value.trim().trim('[', ']') }.lowercase()

    private fun stableId(protocol: String, address: String, port: Int, credential: String, transport: String, security: String, parameters: Map<String, String>): String {
        val semantic = buildString {
            listOf(protocol.lowercase(), normalizedHost(address), port.toString(), credential, transport.lowercase(), security.lowercase()).forEach { append(it.length).append(':').append(it).append('|') }
            parameters.toSortedMap(String.CASE_INSENSITIVE_ORDER).forEach { (key, value) -> append(key.lowercase().length).append(':').append(key.lowercase()).append('=').append(value.length).append(':').append(value).append('|') }
        }
        return MessageDigest.getInstance("SHA-256").digest(semantic.toByteArray(StandardCharsets.UTF_8)).take(12).joinToString("") { "%02x".format(it) }
    }

    private fun inferCountry(name: String): String {
        val points = name.codePoints().toArray()
        for (index in 0 until points.lastIndex) if (points[index] in REGIONAL_RANGE && points[index + 1] in REGIONAL_RANGE) return "${('A'.code + points[index] - REGIONAL_START).toChar()}${('A'.code + points[index + 1] - REGIONAL_START).toChar()}"
        val lower = name.lowercase()
        return linkedMapOf("germany" to "DE", "deutschland" to "DE", "netherlands" to "NL", "holland" to "NL", "finland" to "FI", "turkey" to "TR", "türkiye" to "TR", "france" to "FR", "united states" to "US", "usa" to "US", "canada" to "CA", "united kingdom" to "GB", "singapore" to "SG", "japan" to "JP", "iran" to "IR", "sweden" to "SE").entries.firstOrNull { lower.contains(it.key) }?.value ?: ""
    }

    private val RECOGNIZED_SCHEMES = setOf("vless", "trojan", "vmess", "ss", "socks", "socks5", "http", "https", "hy2", "hysteria2", "hysteria")
    private val SHADOWSOCKS_METHODS = setOf("aes-128-gcm", "aead_aes_128_gcm", "aes-256-gcm", "aead_aes_256_gcm", "chacha20-poly1305", "aead_chacha20_poly1305", "chacha20-ietf-poly1305", "xchacha20-poly1305", "aead_xchacha20_poly1305", "xchacha20-ietf-poly1305", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305")
    private const val REGIONAL_START = 0x1F1E6
    private val REGIONAL_RANGE = REGIONAL_START..0x1F1FF
}

package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.model.SubscriptionUsage
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64

data class SubscriptionParseStats(
    val total: Int,
    val parsed: Int,
    val skipped: Int,
    val failed: Int,
    val duplicates: Int,
) {
    val complete: Boolean get() = parsed > 0 && skipped == 0 && failed == 0

    fun summary(): String =
        "total=$total parsed=$parsed skipped=$skipped failed=$failed duplicates=$duplicates"
}

data class SubscriptionParseResult(
    val servers: List<ServerRecord>,
    val stats: SubscriptionParseStats,
    val failures: List<String>,
)

object SubscriptionParser {
    fun parse(body: String): List<ServerRecord> = parseDetailed(body).servers

    fun parseDetailed(body: String): SubscriptionParseResult {
        val normalized = body.trim().removePrefix("\uFEFF")
        val content = if (normalized.contains("://")) normalized else decodeBase64(normalized) ?: normalized
        val records = linkedMapOf<String, ServerRecord>()
        val failures = mutableListOf<String>()
        var total = 0
        var parsed = 0
        var skipped = 0
        var failed = 0
        var duplicates = 0
        content.lineSequence().map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .forEachIndexed { index, line ->
                total++
                val protocol = line.substringBefore("://", "unknown").lowercase().take(16)
                val record = runCatching {
                    when {
                        line.startsWith("vless://", ignoreCase = true) -> parseStandardUri(line, "vless")
                        line.startsWith("trojan://", ignoreCase = true) -> parseStandardUri(line, "trojan")
                        line.startsWith("vmess://", ignoreCase = true) -> parseVmess(line)
                        else -> null
                    }
                }.onFailure { error ->
                    failed++
                    failures += "entry=${index + 1} protocol=$protocol error=${error.javaClass.simpleName}"
                }.getOrNull()
                if (record == null) {
                    if (protocol !in SUPPORTED_PROTOCOLS) skipped++
                    return@forEachIndexed
                }
                parsed++
                if (records.putIfAbsent(record.id, record) != null) duplicates++
            }
        return SubscriptionParseResult(
            servers = records.values.toList(),
            stats = SubscriptionParseStats(total, parsed, skipped, failed, duplicates),
            failures = failures.take(MAX_REPORTED_FAILURES),
        )
    }

    fun parseUsage(header: String?): SubscriptionUsage {
        if (header.isNullOrBlank()) return SubscriptionUsage()
        val values = header.split(';').mapNotNull { field ->
            val parts = field.trim().split('=', limit = 2)
            if (parts.size == 2) parts[0].lowercase() to parts[1].trim().toLongOrNull() else null
        }.toMap()
        return SubscriptionUsage(
            upload = values["upload"],
            download = values["download"],
            total = values["total"],
            expireEpochSeconds = values["expire"],
        )
    }

    private fun parseStandardUri(raw: String, protocol: String): ServerRecord {
        val uri = URI(raw)
        val query = parseQuery(uri.rawQuery)
        val credential = decode(uri.rawUserInfo ?: error("Missing credential"))
        val host = uri.host ?: error("Missing host")
        val port = uri.port.takeIf { it > 0 } ?: defaultPort(query["security"])
        val transport = query["type"]?.ifBlank { "tcp" } ?: "tcp"
        val security = query["security"]?.ifBlank { "none" } ?: "none"
        val name = decode(uri.rawFragment ?: "Server")
        return ServerRecord(
            id = stableId(raw),
            name = name.ifBlank { "Server" },
            country = inferCountry(name),
            protocol = protocol,
            address = host,
            port = port,
            credential = credential,
            transport = transport,
            security = security,
            parameters = query,
        )
    }

    private fun parseVmess(raw: String): ServerRecord {
        val decoded = decodeBase64(raw.substringAfter("vmess://")) ?: error("Invalid VMess payload")
        val json = JSONObject(decoded)
        val address = json.getString("add")
        val port = json.optString("port").toIntOrNull() ?: json.optInt("port", 443)
        val name = json.optString("ps", "Server")
        val parameters = buildMap {
            val mapping = mapOf(
                "alterId" to "aid", "encryption" to "scy", "host" to "host", "path" to "path",
                "sni" to "sni", "alpn" to "alpn", "fp" to "fp", "flow" to "flow",
                "headerType" to "type",
            )
            mapping.forEach { (target, source) -> json.optString(source).takeIf { it.isNotBlank() }?.let { put(target, it) } }
        }
        return ServerRecord(
            id = stableId(raw),
            name = name,
            country = inferCountry(name),
            protocol = "vmess",
            address = address,
            port = port,
            credential = json.getString("id"),
            transport = json.optString("net", "tcp"),
            security = json.optString("tls", "none").ifBlank { "none" },
            parameters = parameters,
        )
    }

    private fun parseQuery(rawQuery: String?): Map<String, String> {
        if (rawQuery.isNullOrBlank()) return emptyMap()
        return rawQuery.split('&').mapNotNull { part ->
            val pieces = part.split('=', limit = 2)
            if (pieces.isEmpty()) null else decode(pieces[0]) to decode(pieces.getOrElse(1) { "" })
        }.toMap()
    }

    private fun decodeBase64(input: String): String? {
        val compact = input.filterNot(Char::isWhitespace)
        val padded = compact + "=".repeat((4 - compact.length % 4) % 4)
        return listOf(Base64.getUrlDecoder(), Base64.getDecoder()).firstNotNullOfOrNull { decoder ->
            runCatching { String(decoder.decode(padded), StandardCharsets.UTF_8) }.getOrNull()
        }
    }

    // Share links use URI percent-encoding, not HTML form encoding. Preserve a
    // literal '+' instead of letting URLDecoder silently turn it into a space.
    private fun decode(value: String): String = URLDecoder.decode(
        value.replace("+", "%2B"),
        StandardCharsets.UTF_8.name(),
    )

    private fun stableId(raw: String): String = MessageDigest.getInstance("SHA-256")
        .digest(raw.toByteArray(StandardCharsets.UTF_8))
        .take(12)
        .joinToString("") { "%02x".format(it) }

    private fun defaultPort(security: String?): Int = if (security in setOf("tls", "reality")) 443 else 80

    private fun inferCountry(name: String): String {
        val codePoints = name.codePoints().toArray()
        for (index in 0 until codePoints.lastIndex) {
            val first = codePoints[index]
            val second = codePoints[index + 1]
            if (first in REGIONAL_INDICATOR_RANGE && second in REGIONAL_INDICATOR_RANGE) {
                return "${('A'.code + first - REGIONAL_INDICATOR_START).toChar()}" +
                    "${('A'.code + second - REGIONAL_INDICATOR_START).toChar()}"
            }
        }
        val lower = name.lowercase()
        val countries = linkedMapOf(
            "germany" to "DE", "deutschland" to "DE", "netherlands" to "NL", "holland" to "NL",
            "finland" to "FI", "turkey" to "TR", "türkiye" to "TR", "france" to "FR",
            "united states" to "US", "usa" to "US", "canada" to "CA", "united kingdom" to "GB",
            "singapore" to "SG", "japan" to "JP", "iran" to "IR", "sweden" to "SE",
        )
        return countries.entries.firstOrNull { lower.contains(it.key) }?.value ?: ""
    }

    private val SUPPORTED_PROTOCOLS = setOf("vless", "trojan", "vmess")
    private const val MAX_REPORTED_FAILURES = 8
    private const val REGIONAL_INDICATOR_START = 0x1F1E6
    private val REGIONAL_INDICATOR_RANGE = REGIONAL_INDICATOR_START..0x1F1FF
}

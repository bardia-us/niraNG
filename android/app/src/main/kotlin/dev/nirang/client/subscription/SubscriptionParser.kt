package dev.nirang.client.subscription

import android.util.Base64
import dev.nirang.client.model.ServerRecord
import dev.nirang.client.model.SubscriptionUsage
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

object SubscriptionParser {
    fun parse(body: String): List<ServerRecord> {
        val normalized = body.trim().removePrefix("\uFEFF")
        val content = if (normalized.contains("://")) normalized else decodeBase64(normalized) ?: normalized
        return content.lineSequence()
            .map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { line ->
                runCatching {
                    when {
                        line.startsWith("vless://", ignoreCase = true) -> parseStandardUri(line, "vless")
                        line.startsWith("trojan://", ignoreCase = true) -> parseStandardUri(line, "trojan")
                        line.startsWith("vmess://", ignoreCase = true) -> parseVmess(line)
                        else -> null
                    }
                }.getOrNull()
            }
            .distinctBy(ServerRecord::id)
            .toList()
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
                "sni" to "sni", "alpn" to "alpn", "fingerprint" to "fp", "flow" to "flow",
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
        return listOf(Base64.URL_SAFE or Base64.NO_WRAP, Base64.DEFAULT).firstNotNullOfOrNull { flags ->
            runCatching { String(Base64.decode(padded, flags), StandardCharsets.UTF_8) }.getOrNull()
        }
    }

    private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())

    private fun stableId(raw: String): String = MessageDigest.getInstance("SHA-256")
        .digest(raw.toByteArray(StandardCharsets.UTF_8))
        .take(12)
        .joinToString("") { "%02x".format(it) }

    private fun defaultPort(security: String?): Int = if (security in setOf("tls", "reality")) 443 else 80

    private fun inferCountry(name: String): String {
        val lower = name.lowercase()
        val countries = linkedMapOf(
            "germany" to "DE", "deutschland" to "DE", "netherlands" to "NL", "holland" to "NL",
            "finland" to "FI", "turkey" to "TR", "türkiye" to "TR", "france" to "FR",
            "united states" to "US", "usa" to "US", "canada" to "CA", "united kingdom" to "GB",
            "singapore" to "SG", "japan" to "JP", "iran" to "IR", "sweden" to "SE",
        )
        return countries.entries.firstOrNull { lower.contains(it.key) }?.value ?: ""
    }
}

package dev.nirang.client.settings

import java.net.URI

internal object DnsResolverAddress {
    fun normalizeList(value: String): String = value.split(',', '\n').joinToString(",") {
        normalize(it.trim())
    }

    fun normalize(value: String): String {
        val uri = runCatching { URI(value) }.getOrNull() ?: return value
        // Google's RFC8484 endpoint does not accept /dns-query/ (HTTP 404).
        // Never strip arbitrary custom DoH paths, queries, or credentials.
        if (uri.scheme?.lowercase() !in setOf("https", "https+local") ||
            !uri.host.equals("dns.google", ignoreCase = true) ||
            uri.rawPath != "/dns-query/" || uri.rawUserInfo != null ||
            (uri.port != -1 && uri.port != 443)) return value
        val suffixStart = value.indexOfFirst { it == '?' || it == '#' }.let {
            if (it == -1) value.length else it
        }
        return value.removeRange(suffixStart - 1, suffixStart)
    }
}

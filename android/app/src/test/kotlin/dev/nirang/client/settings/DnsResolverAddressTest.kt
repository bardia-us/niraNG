package dev.nirang.client.settings

import org.junit.Assert.assertEquals
import org.junit.Test

class DnsResolverAddressTest {
    @Test
    fun `only the proven broken Google path is corrected without rewriting URI payloads`() {
        val cases = listOf(
            "https://dns.google/dns-query/?padding=a%2Bb#fragment" to
                "https://dns.google/dns-query?padding=a%2Bb#fragment",
            "HTTPS://DNS.GOOGLE:443/dns-query/" to "HTTPS://DNS.GOOGLE:443/dns-query",
            "https+local://dns.google/dns-query/" to "https+local://dns.google/dns-query",
            "https://user:example@dns.google/dns-query/" to "https://user:example@dns.google/dns-query/",
            "https://dns.google:8443/dns-query/" to "https://dns.google:8443/dns-query/",
            "https://dns.google/custom/" to "https://dns.google/custom/",
            "https://dns.google/dns-query" to "https://dns.google/dns-query",
            "https://resolver.example/dns-query/?key=a%2Bb" to "https://resolver.example/dns-query/?key=a%2Bb",
            "1.1.1.1" to "1.1.1.1",
            "tcp+local://[2606:4700:4700::1111]" to "tcp+local://[2606:4700:4700::1111]",
            "not a URI" to "not a URI",
        )
        for ((input, expected) in cases) assertEquals(input, expected, DnsResolverAddress.normalize(input))
    }

    @Test
    fun `resolver lists preserve order scheme and custom paths`() {
        assertEquals("https://dns.google/dns-query,https://resolver.example/custom/?key=a%2Bb,9.9.9.9",
            DnsResolverAddress.normalizeList(" https://dns.google/dns-query/\nhttps://resolver.example/custom/?key=a%2Bb,9.9.9.9"))
    }
}

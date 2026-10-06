package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayRoutingTest {
    @Test
    fun globalBypassesOnlyLocalDestinationsAndKeepsAsIs() {
        val routing = XrayConfigBuilder.buildRouting(
            routingMode = "global",
            domainStrategy = "AsIs",
            enableLocalDns = false,
        )

        assertEquals("AsIs", routing.getString("domainStrategy"))
        assertFalse(routing.toString().contains("domain:ir"))
        assertTrue(directRules(routing).any { it.optJSONArray("ip").strings().contains("192.168.0.0/16") })

        val generated = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(testServer))
        assertEquals(
            "proxy",
            generated.getJSONArray("outbounds").getJSONObject(0).getString("tag"),
        )
        assertFalse(generated.getJSONObject("routing").toString().contains("example.ir"))
    }

    @Test
    fun localDestinationsAlwaysPrecedeQuicAndDnsInterception() {
        listOf("global", "bypassIran", "custom").forEach { mode ->
            val rules = XrayConfigBuilder.buildRouting(
                routingMode = mode,
                iranCidrs = listOf("2.144.0.0/14"),
                blockQuic = true,
            ).getJSONArray("rules").objects()
            val ipIndex = rules.indexOfFirst { it.optJSONArray("ip").strings().contains("192.168.0.0/16") }
            val domainIndex = rules.indexOfFirst { it.optJSONArray("domain").strings().contains("domain:local") }
            val blockedIndex = rules.indexOfFirst { it.optString("outboundTag") == "blocked" }
            val dnsIndex = rules.indexOfFirst { it.optString("outboundTag") == "dns-out" }
            assertTrue("$mode local IP rule missing", ipIndex >= 0)
            assertTrue("$mode local domain rule missing", domainIndex >= 0)
            listOf(ipIndex, domainIndex).forEach { localIndex ->
                assertEquals("direct", rules[localIndex].getString("outboundTag"))
                assertTrue("$mode local must precede QUIC", localIndex < blockedIndex)
                assertTrue("$mode local must precede DNS", localIndex < dnsIndex)
            }
            // Xray ANDs domain/IP conditions within one rule. LAN IPs and local
            // names must work independently, including raw IP connections.
            assertFalse(rules[ipIndex].has("domain"))
            assertFalse(rules[domainIndex].has("ip"))
            assertTrue(rules[ipIndex].getJSONArray("ip").strings().containsAll(listOf(
                "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
                "172.16.0.0/12", "::1/128", "fc00::/7", "fe80::/10",
            )))
        }
    }

    @Test
    fun localDomainsUseSystemDnsWithoutRemoteOrFakeFallbackInEveryMode() {
        listOf("global", "bypassIran", "custom").forEach { mode ->
            val servers = XrayConfigBuilder.buildDnsSettings(
                "https://dns.google/dns-query", true, "9.9.9.9", mode,
                "domain:example.com", true, false,
            ).getJSONArray("servers")
            val local = servers.getJSONObject(0)
            assertEquals("localhost", local.getString("address"))
            assertTrue(local.getBoolean("finalQuery"))
            assertTrue(local.getBoolean("skipFallback"))
            assertEquals(listOf("full:localhost", "domain:localhost", "domain:local"), local.getJSONArray("domains").strings())
        }
    }

    @Test
    fun bypassIranUsesDomainIrAndFrozenCidrs() {
        val cidrs = frozenCidrs()
        assertTrue(cidrs.size > 2_000)
        assertTrue(cidrs.contains("2.57.3.0/24"))
        assertTrue(cidrs.any { it.contains(':') })

        val routing = XrayConfigBuilder.buildRouting(
            routingMode = "bypassIran",
            iranCidrs = cidrs,
            enableLocalDns = false,
        )
        val direct = directRules(routing)
        val domains = direct.flatMap { it.optJSONArray("domain").strings() }
        val ips = direct.flatMap { it.optJSONArray("ip").strings() }

        assertTrue(domains.contains("domain:ir"))
        assertTrue(domains.contains("full:localhost"))
        assertTrue(ips.contains("10.0.0.0/8"))
        assertTrue(ips.contains("fc00::/7"))
        assertTrue(ips.contains("2.57.3.0/24"))
        assertFalse(routing.toString().contains("geosite:ir", ignoreCase = true))
        assertFalse(routing.toString().contains("geoip:ir", ignoreCase = true))
        assertFalse(routing.toString().contains("geoip:", ignoreCase = true))
    }

    @Test
    fun customRoutesValidatedDomainAndIpRulesDirectly() {
        val routing = XrayConfigBuilder.buildRouting(
            routingMode = "custom",
            customDomains = "domain:example.com\nfull:api.example.com\nregexp:^(api|www){1,3}\\.example\\.net$",
            customIps = "1.2.3.4\n1.2.3.0/24\n2001:db8::/32",
            enableLocalDns = false,
        )
        val direct = directRules(routing)
        val serialized = direct.joinToString()

        assertTrue(serialized.contains("domain:example.com"))
        assertTrue(serialized.contains("{1,3}"))
        assertTrue(serialized.contains("1.2.3.0/24"))
        assertTrue(serialized.contains("2001:db8::/32"))
        assertFalse(direct.any { it.has("ip") && it.has("domain") })
        assertFalse(serialized.contains("geosite:ir", ignoreCase = true))
        assertFalse(serialized.contains("geoip:ir", ignoreCase = true))
    }

    @Test
    fun generatedRoutingPassesPreStartValidation() {
        val routing = XrayConfigBuilder.buildRouting(
            routingMode = "bypassIran",
            iranCidrs = frozenCidrs(),
            enableLocalDns = false,
        )
        val root = JSONObject()
            .put(
                "outbounds",
                JSONArray()
                    .put(JSONObject().put("tag", "proxy"))
                    .put(JSONObject().put("tag", "direct")),
            )
            .put("routing", routing)

        XrayConfigBuilder.validateGeneratedConfig(root.toString())
    }

    private fun frozenCidrs(): List<String> = listOf(
        "routing/iran_ipv4.txt",
        "routing/iran_ipv6.txt",
    ).flatMap { resource ->
        requireNotNull(javaClass.classLoader?.getResourceAsStream(resource)) {
            "Missing test routing resource: $resource"
        }.bufferedReader().useLines(IranCidrRepository::parse)
    }

    private fun directRules(routing: JSONObject): List<JSONObject> =
        routing.getJSONArray("rules").objects()
            .filter { it.optString("outboundTag") == "direct" }

    private fun JSONArray?.strings(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).map(::getString)
    }

    private fun JSONArray.objects(): List<JSONObject> =
        (0 until length()).map(::getJSONObject)

    private val testServer = ServerRecord(
        id = "test",
        name = "Test",
        country = "DE",
        protocol = "vless",
        address = "example.com",
        port = 443,
        credential = "00000000-0000-0000-0000-000000000000",
        transport = "tcp",
        security = "tls",
        parameters = mapOf("sni" to "example.com"),
    )
}

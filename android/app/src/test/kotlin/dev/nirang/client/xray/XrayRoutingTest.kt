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
    fun globalHasNoDirectDestinationRulesAndKeepsAsIs() {
        val routing = XrayConfigBuilder.buildRouting(
            routingMode = "global",
            domainStrategy = "AsIs",
            enableLocalDns = false,
        )

        assertEquals("AsIs", routing.getString("domainStrategy"))
        assertFalse(routing.toString().contains("domain:ir"))
        assertFalse(directRules(routing).any())

        val generated = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(testServer))
        assertEquals(
            "proxy",
            generated.getJSONArray("outbounds").getJSONObject(0).getString("tag"),
        )
        assertFalse(generated.getJSONObject("routing").toString().contains("example.ir"))
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

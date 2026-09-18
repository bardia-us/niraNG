package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import java.nio.charset.StandardCharsets
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionParserTest {
    @Test
    fun `mixed VLESS and Trojan CDN profiles parse completely from base64`() {
        val vless =
            "vless://00000000-0000-4000-8000-000000000001@104.16.0.1:443" +
                "?security=tls&type=ws&host=cdn.example.com&sni=origin.example.com" +
                "&path=%2Fedge%3Fed%3D2560&alpn=http%2F1.1&allowInsecure=1" +
                "&fp=unsafe&cs=TLS_AES_128_GCM_SHA256" +
                "&fm=%7B%22tcp%22%3A%5B%7B%22type%22%3A%22fragment%22%2C%22settings%22%3A%7B%7D%7D%5D%7D" +
                "&future=value%2Bkept#%F0%9F%87%B3%F0%9F%87%B1%20CDN"
        val trojan =
            "trojan://secret@example.net:443?security=tls&type=ws" +
                "&host=edge.example.net&path=%2Fws&sni=edge.example.net#France"
        val encoded = Base64.getEncoder().encodeToString(
            "$vless\n$trojan\n".toByteArray(StandardCharsets.UTF_8),
        )

        val result = SubscriptionParser.parseDetailed(encoded)

        assertTrue(result.stats.complete)
        assertEquals(2, result.stats.total)
        assertEquals(2, result.servers.size)
        assertEquals("NL", result.servers.first().country)
        assertEquals("unsafe", result.servers.first().parameters["fp"])
        assertEquals("TLS_AES_128_GCM_SHA256", result.servers.first().parameters["cs"])
        assertEquals("{\"tcp\":[{\"type\":\"fragment\",\"settings\":{}}]}", result.servers.first().parameters["fm"])
        assertEquals("1", result.servers.first().parameters["allowInsecure"])
        assertEquals("value+kept", result.servers.first().parameters["future"])
        assertEquals("ws", result.servers.last().transport)
    }

    @Test
    fun `Reality XHTTP profile remains independent from WS TLS`() {
        val profile = SubscriptionParser.parseDetailed(
            "vless://00000000-0000-4000-8000-000000000002@example.com:443" +
                "?security=reality&type=xhttp&sni=example.com&pbk=public-key&sid=abcd" +
                "&path=%2Fxhttp&mode=auto&fp=chrome#Sweden",
        ).servers.single()

        assertEquals("xhttp", profile.transport)
        assertEquals("reality", profile.security)
        assertEquals("public-key", profile.parameters["pbk"])
        assertEquals("chrome", profile.parameters["fp"])
    }

    @Test
    fun `malformed and unsupported entries are counted instead of hiding valid profiles`() {
        val valid =
            "vless://00000000-0000-4000-8000-000000000001@example.com:443" +
                "?security=tls&type=ws&host=cdn.example.com&path=%2Fws#Germany"
        val body = "$valid\nvless://missing-host\nwireguard://unsupported\n$valid"

        val result = SubscriptionParser.parseDetailed(body)

        assertFalse(result.stats.complete)
        assertEquals(4, result.stats.total)
        assertEquals(2, result.stats.parsed)
        assertEquals(1, result.stats.failed)
        assertEquals(1, result.stats.skipped)
        assertEquals(1, result.stats.duplicates)
        assertEquals(1, result.servers.size)
        assertTrue(result.failures.single().contains("protocol=vless"))
    }

    @Test
    fun `Shadowsocks SIP002 keeps special password and unicode name`() {
        val userInfo = Base64.getUrlEncoder().withoutPadding().encodeToString(
            "chacha20-ietf-poly1305:p@ss:+/word".toByteArray(StandardCharsets.UTF_8),
        )
        val result = SubscriptionParser.parseDetailed(
            "ss://$userInfo@edge.example.com:8388#%F0%9F%87%AF%F0%9F%87%B5%20%E6%9D%B1%E4%BA%AC",
        )
        val server = result.servers.single()

        assertEquals("shadowsocks", server.protocol)
        assertEquals("chacha20-ietf-poly1305", server.parameters["method"])
        assertEquals("p@ss:+/word", server.credential)
        assertEquals("🇯🇵 東京", server.name)
        assertTrue(result.stats.complete)
    }

    @Test
    fun `legacy Shadowsocks payload parses and unsupported plugin is isolated`() {
        val legacy = Base64.getUrlEncoder().withoutPadding().encodeToString(
            "aes-256-gcm:secret@ss.example.com:443".toByteArray(StandardCharsets.UTF_8),
        )
        val result = SubscriptionParser.parseDetailed(
            "ss://$legacy#Legacy\nss://YWVzLTEyOC1nY206cGFzcw@bad.example:443?plugin=obfs-local#Bad",
        )

        assertEquals(1, result.servers.size)
        assertEquals("aes-256-gcm", result.servers.single().parameters["method"])
        assertEquals(1, result.stats.failed)
    }

    @Test
    fun `identity preserves renamed connections and tracks config changes`() {
        val first = SubscriptionParser.parseDetailed(
            "vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&type=ws&path=%2Fa#Old",
        ).servers.single()
        val renamed = SubscriptionParser.parseDetailed(
            "vless://00000000-0000-4000-8000-000000000001@example.com:443?path=%2Fa&type=ws&security=tls#New",
        ).servers.single()
        val changed = SubscriptionParser.parseDetailed(
            "vless://00000000-0000-4000-8000-000000000001@example.com:443?path=%2Fb&type=ws&security=tls#New",
        ).servers.single()

        assertFalse(first.id == renamed.id)
        assertFalse(first.id == changed.id)
    }

    @Test
    fun `same connection with different names is preserved while exact duplicate is removed`() {
        val base = "vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&type=ws&path=%2Fa"
        val result = SubscriptionParser.parseDetailed(
            listOf("$base#Amsterdam", "$base#Stockholm", "$base#Amsterdam").joinToString("\n"),
        )

        assertEquals(listOf("Amsterdam", "Stockholm"), result.servers.map { it.name })
        assertEquals(1, result.stats.duplicates)
    }

    @Test
    fun `mixed supported subscription keeps usable protocols without WireGuard`() {
        val ssUser = Base64.getUrlEncoder().withoutPadding().encodeToString(
            "aes-128-gcm:pass".toByteArray(StandardCharsets.UTF_8),
        )
        val body = listOf(
            "ss://$ssUser@ss.example.com:8388#SS",
            "socks://user:pass@socks.example.com:1080#SOCKS",
            "http://user:pass@http.example.com:8080#HTTP",
            "hysteria2://auth@hy.example.com:443?sni=hy.example.com#HY2",
            "hysteria://auth@old.example.com:443#Unsupported-v1",
            "wireguard://unsupported",
        ).joinToString("\n")

        val result = SubscriptionParser.parseDetailed(body)

        assertEquals(listOf("shadowsocks", "socks", "http", "hysteria2"), result.servers.map { it.protocol })
        assertEquals(2, result.stats.skipped)
    }

    @Test
    fun `repeated mixed refresh keeps source order when Shadowsocks changes`() {
        val vless = "vless://00000000-0000-4000-8000-000000000001@first.example.com:443?security=tls&type=ws#First"
        val vmessJson = """{"v":"2","ps":"VMess","add":"vm.example.com","port":"443","id":"00000000-0000-4000-8000-000000000002","net":"ws","tls":"tls"}"""
        val vmess = "vmess://${Base64.getEncoder().encodeToString(vmessJson.toByteArray())}"
        val trojan = "trojan://secret@tr.example.com:443?security=tls&type=tcp#Trojan"
        fun shadowsocks(password: String): String {
            val user = Base64.getUrlEncoder().withoutPadding().encodeToString(
                "chacha20-ietf-poly1305:$password".toByteArray(),
            )
            return "ss://$user@ss.example.com:8388#Shadowsocks"
        }
        val firstBody = listOf(vless, vmess, trojan, shadowsocks("old")).joinToString("\n")
        val secondBody = listOf(vless, vmess, trojan, shadowsocks("new")).joinToString("\n")

        val firstRefresh = SubscriptionParser.parseDetailed(firstBody).servers
        val identicalRefresh = SubscriptionParser.parseDetailed(firstBody).servers
        val changedRefresh = SubscriptionParser.parseDetailed(secondBody).servers

        assertEquals(firstRefresh.map(ServerRecord::id), identicalRefresh.map(ServerRecord::id))
        assertEquals(listOf("vless", "vmess", "trojan", "shadowsocks"), changedRefresh.map { it.protocol })
        assertEquals("First", changedRefresh.first().name)
        assertEquals("Shadowsocks", changedRefresh.last().name)
    }

    @Test
    fun `literal plus signs survive URI decoding`() {
        val result = SubscriptionParser.parseDetailed(
            "trojan://pass+word@example.net:443?security=tls&type=ws&future=a+b#CDN",
        ).servers.single()

        assertEquals("pass+word", result.credential)
        assertEquals("a+b", result.parameters["future"])
    }

    @Test
    fun `FinalMask arrays survive share link decoding without semantic changes`() {
        val raw =
            "{\"tcp\":[{\"type\":\"fragment\",\"settings\":{" +
                "\"packets\":\"tlshello\",\"lengths\":[\"5\",\"94\",\"1\"]," +
                "\"delays\":[\"0\"],\"maxSplit\":\"0\"}}]}"
        val encoded = java.net.URLEncoder.encode(raw, StandardCharsets.UTF_8.name())
        val profile = SubscriptionParser.parseDetailed(
            "vless://00000000-0000-4000-8000-000000000003@example.com:443" +
                "?security=tls&type=ws&path=%2F&fm=$encoded#FinalMask",
        ).servers.single()

        assertEquals(raw, profile.parameters["fm"])
    }
}

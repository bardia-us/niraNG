package dev.nirang.client.cores.aether

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class AetherParityTest {
    @Test fun `reported endpoints are parsed without exposing arbitrary output`() {
        assertEquals(mapOf("endpoint" to "162.159.199.65:443"), AetherEndpoint.parse("masque", "selected MASQUE gateway 162.159.199.65:443"))
        assertEquals(mapOf("endpoint" to "162.159.192.1:443", "innerEndpoint" to "162.159.193.1:443"),
            AetherEndpoint.parse("masque-in-masque", "masque-in-masque ready: 162.159.192.1:443 (outer) and 162.159.193.1:443 (inner)"))
        assertNull(AetherEndpoint.parse("masque", "selected MASQUE gateway 127.0.0.1:443"))
        assertNull(AetherEndpoint.parse("masque", "private-key=not-a-status"))
    }
    @Test fun `real edge pools and retained endpoints are reported`() {
        assertEquals(mapOf("endpoint" to "188.114.96.1:2408"), AetherEndpoint.parse("wireguard", "using cloudflare edge 188.114.96.1:2408"))
        assertEquals(mapOf("endpoint" to "162.159.36.1:443"), AetherEndpoint.parse("masque", "using cloudflare edge 162.159.36.1:443"))
    }
    @Test fun `dual stack and nested modes reach the native runtime`() {
        for (mode in listOf("masque", "wireguard", "wireguard-over-masque", "warp-in-warp", "masque-in-masque")) {
            val value = AetherOptions.parse("""{"mode":"$mode","ipFamily":"both"}""")
            val args = value.arguments(File("private"),10819,10821,0)
            assertEquals("both",args[args.indexOf("--ip")+1])
            if (mode == "warp-in-warp") assertTrue("--gool-classic" in args)
            if (mode == "masque-in-masque") assertTrue("--mim" in args)
            assertTrue("--tls-verify" in args)
        }
    }
    @Test fun `fingerprint is real TLS flags and raw WireGuard rejects it`() {
        val args=AetherOptions.parse("""{"fingerprint":"firefox"}""").arguments(File("private"),10819,10821,0)
        assertTrue("--tls-ciphers" in args)
        assertTrue("--disable-grease" in args)
        assertThrows(IllegalArgumentException::class.java) { AetherOptions.parse("""{"mode":"wireguard","fingerprint":"firefox"}""") }
    }
    @Test fun `nested identities have separate files and endpoints`() {
        val o=AetherOptions.parse("""{"mode":"masque-in-masque","outerEndpoint":"162.159.192.1:443","innerEndpoint":"162.159.193.1:443"}""")
        assertEquals(listOf("aether-masque.toml","aether-masque-secondary.toml"),o.identityFiles)
        val args=o.arguments(File("private"),10819,10821,0)
        assertEquals("162.159.192.1:443",args[args.indexOf("--mim-outer")+1])
        assertEquals("162.159.193.1:443",args[args.indexOf("--mim-inner")+1])
    }
}

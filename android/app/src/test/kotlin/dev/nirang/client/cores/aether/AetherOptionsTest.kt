package dev.nirang.client.cores.aether

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class AetherOptionsTest {
    @Test fun `official regions beyond the old shortlist are supported`() {
        for(region in listOf("JP","AU","BR","SG","ZA")) {
            val args=AetherOptions.parse("{\"psiphon\":\"chain\",\"psiphonRegion\":\"$region\"}").arguments(File("private"),10819,10821,0)
            assertEquals(region,args[args.indexOf("--psiphon-region")+1])
        }
    }
    @Test fun `Psiphon shape is a typed upstream option`() {
        val args = AetherOptions.parse("{\"psiphon\":\"chain\",\"psiphonMode\":\"cdn\"}")
            .arguments(File("private"), 10819,10821,0)
        assertEquals("cdn", args[args.indexOf("--psiphon-mode") + 1])
        assertThrows(IllegalArgumentException::class.java) { AetherOptions.parse("{\"psiphonMode\":\"arbitrary\"}") }
    }

    @Test fun `Psiphon region is bounded and auto leaves country unset`() {
        val args = AetherOptions.parse("{\"psiphon\":\"chain\",\"psiphonRegion\":\"DE\"}")
            .arguments(File("private"),10819,10821,0)
        assertEquals("DE", args[args.indexOf("--psiphon-region") + 1])
        assertFalse("--psiphon-region" in AetherOptions.parse("{}").arguments(File("private"),10819,10821,0))
        assertThrows(IllegalArgumentException::class.java) { AetherOptions.parse("{\"psiphonRegion\":\"ZZ\"}") }
    }
    @Test fun `unknown or process control fields are rejected`() {
        for (value in listOf("{\"args\":[\"--tls-verify\"]}", "{\"tlsVerify\":false}",
            "{\"apiAddress\":\"evil.invalid\"}", "{\"mode\":\"masque\",\"mtu\":1400}")) {
            assertThrows(IllegalArgumentException::class.java) { AetherOptions.parse(value) }
        }
    }

    @Test fun `strict types ranges and protocol combinations are checked`() {
        for (value in listOf("{\"keepalive\":\"5\"}", "{\"keepalive\":5.5}",
            "{\"startupTimeoutSeconds\":301}", "{\"endpoint\":\"127.0.0.1:443\"}",
            "{\"endpoint\":\"evil.invalid:443\"}",
            "{\"mode\":\"wireguard\",\"psiphon\":\"reverse\"}",
            "{\"mode\":\"wireguard\",\"carrier\":\"h2\"}")) {
            assertThrows(value, IllegalArgumentException::class.java) { AetherOptions.parse(value) }
        }
    }

    @Test fun `real modes build argument arrays with pinned security and local listeners`() {
        for ((mode, flag) in mapOf("masque" to "--masque", "wireguard" to "--wg",
            "wireguard-over-masque" to "--gool")) {
            val options = AetherOptions.parse("{\"mode\":\"$mode\",\"endpoint\":\"162.159.198.3:443\"}")
            val args = options.arguments(File("private"), 10819, 10821, 10823)
            assertTrue(flag in args)
            assertTrue("--tls-verify" in args)
            assertEquals("socks5://127.0.0.1:10823", args[args.indexOf("--upstream") + 1])
            assertEquals("127.0.0.1:10819", args[args.indexOf("--bind") + 1])
            assertFalse(args.any { it.contains(';') || it.contains('\n') })
        }
    }

    @Test fun `provision uses separate native identity files and chain output reaches Psiphon`() {
        assertEquals(listOf("aether-masque.toml"), AetherOptions.parse("{}").identityFiles)
        assertEquals(listOf("aether-wg.toml"), AetherOptions.parse("{\"mode\":\"wireguard\"}").identityFiles)
        assertEquals(listOf("aether-masque.toml", "aether-masque-gool.toml"),
            AetherOptions.parse("{\"mode\":\"wireguard-over-masque\"}").identityFiles)
        assertEquals(emptyList<String>(), AetherOptions.parse("{\"psiphon\":\"only\"}").identityFiles)
        assertEquals(10821, AetherOptions.parse("{\"psiphon\":\"chain\"}").outputPort(10819,10821))
        assertEquals(10819, AetherOptions.parse("{\"psiphon\":\"reverse\"}").outputPort(10819,10821))
    }
}

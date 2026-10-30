package dev.nirang.client.cores.aether

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class AetherIdentityStoreTest {
    @Test fun `replacement accepts real matching certificate in multiline and escaped TOML`() {
        for(multiline in listOf(false,true)) {
            val directory=Files.createTempDirectory("aether-valid-pem").toFile()
            try {
                val cert=javaClass.getResource("/aether-test-identity/cert.pem")!!.readText()
                val key=javaClass.getResource("/aether-test-identity/key.pem")!!.readText()
                fun pemField(name:String,value:String):String=if(multiline) "$name = '''\n$value'''\n"
                    else "$name = \"${value.replace("\n","\\n")}\"\n"
                val identity=wireguard()+"cert_issued_at = ${System.currentTimeMillis()/1000}\n"+pemField("cert_pem",cert)+pemField("key_pem",key)
                val store=AetherIdentityStore(directory)
                val options=AetherOptions.parse("{\"mode\":\"masque\"}")
                store.ensure(options,{},forceRenew=true) { staging -> File(staging,"aether-masque.toml").writeText(identity) }
                store.ensure(options,{}) { fail("Matching identity should be reusable offline") }
                assertEquals(identity,File(directory,"aether-masque.toml").readText())
            } finally { directory.deleteRecursively() }
        }
    }

    @Test fun `valid certificate with mismatched private key is rejected`() {
        val directory=Files.createTempDirectory("aether-wrong-key").toFile()
        try {
            val cert=javaClass.getResource("/aether-test-identity/cert.pem")!!.readText()
            val key=javaClass.getResource("/aether-test-identity/mismatched-key.pem")!!.readText()
            assertThrows(IllegalStateException::class.java) {
                AetherIdentityStore(directory).ensure(AetherOptions.parse("{\"mode\":\"masque\"}"),{},forceRenew=true) { staging ->
                    File(staging,"aether-masque.toml").writeText(wireguard()+"cert_issued_at = ${System.currentTimeMillis()/1000}\ncert_pem = '''\n$cert'''\nkey_pem = '''\n$key'''\n")
                }
            }
            assertFalse(File(directory,"aether-masque.toml").exists())
        } finally { directory.deleteRecursively() }
    }
    @Test fun `waiting for another registration remains cancellable`() {
        val directory=Files.createTempDirectory("aether-lock").toFile()
        val entered=java.util.concurrent.CountDownLatch(1)
        val release=java.util.concurrent.CountDownLatch(1)
        val cancelled=java.util.concurrent.atomic.AtomicBoolean(false)
        val finished=java.util.concurrent.CountDownLatch(1)
        val options=AetherOptions.parse("{\"mode\":\"wireguard\"}")
        val first=Thread {
            AetherIdentityStore(directory).ensure(options,{}) { staging ->
                entered.countDown(); release.await()
                File(staging,"aether-wg.toml").writeText(wireguard())
            }
        }
        try {
            first.start(); assertTrue(entered.await(3,java.util.concurrent.TimeUnit.SECONDS))
            val second=Thread {
                try {
                    AetherIdentityStore(directory).ensure(options,{
                        if(cancelled.get()) throw java.util.concurrent.CancellationException()
                    }) { fail("Cancelled wait must not register") }
                } catch(_:java.util.concurrent.CancellationException) { finished.countDown() }
            }
            second.start(); cancelled.set(true)
            assertTrue("Cancellation must not wait for network provisioning",finished.await(2,java.util.concurrent.TimeUnit.SECONDS))
            second.join(3000)
        } finally { release.countDown(); first.join(3000); directory.deleteRecursively() }
    }

    @Test fun `truncated certificate cannot replace retained masque identity`() {
        val directory=Files.createTempDirectory("aether-invalid-pem").toFile()
        try {
            val old=File(directory,"aether-masque.toml").apply { writeText("retained identity") }
            assertThrows(IllegalStateException::class.java) {
                AetherIdentityStore(directory).ensure(AetherOptions.parse("{\"mode\":\"masque\"}"),{},forceRenew=true) { staging ->
                    File(staging,old.name).writeText(wireguard()+"cert_issued_at = ${System.currentTimeMillis()/1000}\ncert_pem = \"-----BEGIN CERTIFICATE-----\"\nkey_pem = \"-----BEGIN PRIVATE KEY-----\"\n")
                }
            }
            assertEquals("retained identity",old.readText())
        } finally { directory.deleteRecursively() }
    }

    @Test fun `interrupted multi identity promotion recovers complete previous generation`() {
        val directory=Files.createTempDirectory("aether-recovery").toFile()
        try {
            val stage=File(directory,".provision-12345678-1234-1234-1234-123456789012").apply{mkdir()}
            val backup=File(stage,"before").apply{mkdir()}
            File(backup,"aether-masque.toml").writeText("old masque")
            File(backup,"aether-masque-gool.toml").writeText("old gool")
            File(directory,"aether-masque.toml").writeText("new masque")
            File(directory,"aether-masque-gool.toml").writeText("old gool")
            File(directory,".identity-transaction").writeText(stage.name+"\naether-masque.toml:present\naether-masque-gool.toml:present\n")
            val destination=File(directory,"probe").apply{mkdir()}
            AetherIdentityStore(directory).copyRetained(AetherOptions.parse("{\"mode\":\"wireguard-over-masque\"}"),destination)
            assertEquals("old masque",File(destination,"aether-masque.toml").readText())
            assertEquals("old gool",File(destination,"aether-masque-gool.toml").readText())
            assertTrue(File(directory,".identity-transaction").exists())
            assertEquals("new masque",File(directory,"aether-masque.toml").readText())
            assertThrows(IllegalStateException::class.java) {
                AetherIdentityStore(directory).ensure(AetherOptions.parse("{\"mode\":\"wireguard-over-masque\"}"),{}) { throw IllegalStateException("offline") }
            }
            assertEquals("old masque",File(directory,"aether-masque.toml").readText())
            assertEquals("old gool",File(directory,"aether-masque-gool.toml").readText())
            assertFalse(File(directory,".identity-transaction").exists())
        } finally { directory.deleteRecursively() }
    }
    @Test fun `explicit refresh starts without old identity and replaces only after success`() {
        val directory = Files.createTempDirectory("aether-renew").toFile()
        try {
            val old = File(directory,"aether-wg.toml").apply { writeText(wireguard()) }
            val replacement = wireguard().replace("device_id = \"device\"", "device_id = \"renewed\"")
            AetherIdentityStore(directory).ensure(AetherOptions.parse("{\"mode\":\"wireguard\"}"), {}, forceRenew = true) { staging ->
                assertFalse(File(staging,old.name).exists())
                assertEquals(wireguard(),old.readText())
                File(staging,old.name).writeText(replacement)
            }
            assertEquals(replacement,old.readText())
        } finally { directory.deleteRecursively() }
    }

    @Test fun `failed explicit refresh keeps valid retained key`() {
        val directory = Files.createTempDirectory("aether-renew-failure").toFile()
        try {
            val old = File(directory,"aether-wg.toml").apply { writeText(wireguard()) }
            assertThrows(IllegalStateException::class.java) {
                AetherIdentityStore(directory).ensure(AetherOptions.parse("{\"mode\":\"wireguard\"}"), {}, forceRenew = true) { staging ->
                    File(staging,old.name).writeText("invalid registration")
                }
            }
            assertEquals(wireguard(),old.readText())
        } finally { directory.deleteRecursively() }
    }
    @Test fun `retained identities skip offline provision and prepare start duplicates`() {
        val directory = Files.createTempDirectory("aether-identities").toFile()
        try {
            val store = AetherIdentityStore(directory)
            val options = AetherOptions.parse("{\"mode\":\"wireguard\"}")
            var registrations = 0
            repeat(2) { store.ensure(options, {}) { staging ->
                registrations++
                File(staging, "aether-wg.toml").writeText(wireguard())
            } }
            assertEquals(1, registrations)
        } finally { directory.deleteRecursively() }
    }

    @Test fun `failed registration cannot replace existing private keys`() {
        val directory = Files.createTempDirectory("aether-identities").toFile()
        try {
            val retained = File(directory, "aether-masque.toml").apply { writeText("retained old identity") }
            val options = AetherOptions.parse("{\"mode\":\"wireguard-over-masque\"}")
            assertThrows(IllegalStateException::class.java) {
                AetherIdentityStore(directory).ensure(options, {}) { staging ->
                    File(staging, retained.name).writeText("partly registered replacement")
                    throw IllegalStateException("offline")
                }
            }
            assertEquals("retained old identity", retained.readText())
            assertFalse(File(directory, "aether-masque-gool.toml").exists())
        } finally { directory.deleteRecursively() }
    }

    private fun wireguard(): String {
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(32) { 7 })
        return "device_id = \"device\"\naccess_token = \"token\"\nwg_private_key = \"$key\"\nwg_peer_public_key = \"$key\"\n"
    }
}

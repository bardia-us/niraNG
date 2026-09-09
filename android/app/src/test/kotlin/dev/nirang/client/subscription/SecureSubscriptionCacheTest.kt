package dev.nirang.client.subscription

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.spec.SecretKeySpec

class SecureSubscriptionCacheTest {
    @Test
    fun `encrypted envelope does not expose credentials and round trips`() {
        val plaintext = "{\"credential\":\"00000000-0000-4000-8000-000000000001\"}"
        val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")

        val encrypted = SecureSubscriptionCache.encrypt(plaintext, key)

        assertFalse(encrypted.toString(Charsets.ISO_8859_1).contains("credential"))
        assertFalse(encrypted.toString(Charsets.ISO_8859_1).contains("00000000"))
        assertTrue(encrypted.size > plaintext.length)
        assertTrue(SecureSubscriptionCache.decrypt(encrypted, key) == plaintext)
    }
}

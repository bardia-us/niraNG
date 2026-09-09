package dev.nirang.client.subscription

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object SecureSubscriptionCache {
    private const val KEY_ALIAS = "nirang_subscription_cache_v1"
    private val MAGIC = "NIRANG-CACHE-1\n".toByteArray(Charsets.US_ASCII)

    data class Decoded(val text: String, val wasPlaintext: Boolean)

    fun read(file: File): Decoded {
        val bytes = file.readBytes()
        if (!bytes.startsWith(MAGIC)) return Decoded(bytes.toString(Charsets.UTF_8), true)
        return Decoded(decrypt(bytes, secretKey()), false)
    }

    fun writeAtomic(file: File, text: String) {
        val encrypted = encrypt(text, secretKey())
        val temporary = File(file.parentFile, "${file.name}.tmp")
        FileOutputStream(temporary).use { output ->
            output.write(encrypted)
            output.fd.sync()
        }
        if (!temporary.renameTo(file)) {
            FileOutputStream(file).use { output ->
                output.write(encrypted)
                output.fd.sync()
            }
            temporary.delete()
        }
    }

    internal fun encrypt(text: String, key: SecretKey): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val ciphertext = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        return MAGIC + cipher.iv + ciphertext
    }

    internal fun decrypt(envelope: ByteArray, key: SecretKey): String {
        require(envelope.startsWith(MAGIC) && envelope.size > MAGIC.size + 12) {
            "Subscription cache envelope is invalid"
        }
        val ivStart = MAGIC.size
        val ciphertextStart = ivStart + 12
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(128, envelope.copyOfRange(ivStart, ciphertextStart)),
        )
        return String(cipher.doFinal(envelope.copyOfRange(ciphertextStart, envelope.size)), Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }
}

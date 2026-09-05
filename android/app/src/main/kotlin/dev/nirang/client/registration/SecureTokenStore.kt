package dev.nirang.client.registration

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Small Keystore-backed store; only ciphertext and expiry are kept in SharedPreferences. */
internal object SecureTokenStore {
    private const val KEY_ALIAS = "nirang_api_access_token_v1"
    private const val PREFS = "nirang_installation"
    private const val TOKEN_CIPHERTEXT = "remoteAccessTokenEncrypted"
    private const val TOKEN_EXPIRY = "remoteAccessTokenExpiresAt"

    fun put(context: Context, token: String, expiresAtMillis: Long) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        val combined = cipher.iv + encrypted
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(TOKEN_CIPHERTEXT, Base64.encodeToString(combined, Base64.NO_WRAP))
            .putLong(TOKEN_EXPIRY, expiresAtMillis)
            .remove("remoteAccessToken")
            .apply()
    }

    fun get(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getLong(TOKEN_EXPIRY, 0L) <= System.currentTimeMillis()) {
            clear(context)
            return null
        }
        return runCatching {
            val combined = Base64.decode(prefs.getString(TOKEN_CIPHERTEXT, null), Base64.NO_WRAP)
            require(combined.size > 12)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, combined.copyOfRange(0, 12)))
            String(cipher.doFinal(combined.copyOfRange(12, combined.size)), Charsets.UTF_8)
        }.getOrElse {
            clear(context)
            null
        }
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(TOKEN_CIPHERTEXT)
            .remove(TOKEN_EXPIRY)
            .remove("remoteAccessToken")
            .apply()
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
}

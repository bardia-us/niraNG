package dev.nirang.client.vpn

import android.content.Context
import android.util.Base64
import java.security.SecureRandom

/** One-shot authorization for the exported launcher activity's tile hand-off. */
object TileConnectAuthorization {
    private const val PREFS = "nirang_tile_authorization"
    private const val TOKEN = "token"
    private const val ISSUED_AT = "issuedAt"
    private const val MAX_AGE_MS = 2 * 60 * 1000L

    fun issue(context: Context): String {
        val bytes = ByteArray(24).also(SecureRandom()::nextBytes)
        val token = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(TOKEN, token)
            .putLong(ISSUED_AT, System.currentTimeMillis())
            .commit()
        return token
    }

    fun consume(context: Context, candidate: String?): Boolean {
        if (candidate.isNullOrBlank()) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val expected = prefs.getString(TOKEN, null)
        val issuedAt = prefs.getLong(ISSUED_AT, 0L)
        prefs.edit().clear().commit()
        val age = System.currentTimeMillis() - issuedAt
        return age in 0..MAX_AGE_MS && constantTimeEquals(expected, candidate)
    }

    private fun constantTimeEquals(expected: String?, candidate: String): Boolean {
        if (expected == null || expected.length != candidate.length) return false
        var difference = 0
        expected.indices.forEach { difference = difference or (expected[it].code xor candidate[it].code) }
        return difference == 0
    }
}

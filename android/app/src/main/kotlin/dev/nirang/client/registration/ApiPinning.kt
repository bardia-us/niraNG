package dev.nirang.client.registration

import android.util.Base64
import dev.nirang.client.BuildConfig
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/** Default platform trust plus API-only SPKI pinning. */
internal object ApiPinning {
    val socketFactory by lazy {
        val context = SSLContext.getInstance("TLS")
        context.init(null, arrayOf(PinnedTrustManager()), SecureRandom())
        context.socketFactory
    }

    private class PinnedTrustManager : X509TrustManager {
        private val delegate: X509TrustManager = TrustManagerFactory
            .getInstance(TrustManagerFactory.getDefaultAlgorithm())
            .apply { init(null as KeyStore?) }
            .trustManagers
            .filterIsInstance<X509TrustManager>()
            .first()
        private val pins = BuildConfig.API_SPKI_PINS.split(',').map(String::trim).filter(String::isNotBlank).toSet()

        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
            delegate.checkClientTrusted(chain, authType)

        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
            delegate.checkServerTrusted(chain, authType)
            if (pins.size < 2 || chain.none { certificate -> spkiPin(certificate) in pins }) {
                throw CertificateException("niraNG API public-key pin verification failed")
            }
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers

        private fun spkiPin(certificate: X509Certificate): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(certificate.publicKey.encoded)
            return "sha256/${Base64.encodeToString(digest, Base64.NO_WRAP)}"
        }
    }
}

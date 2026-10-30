package dev.nirang.client.cores.aether

import java.security.KeyStore
import java.security.cert.CertificateFactory
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import org.junit.Assert.*
import org.junit.Test

class AetherCaBundleTest {
    @Test fun `platform roots become a real parseable PEM bundle without duplicates`() {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as KeyStore?)
        val roots = factory.trustManagers.filterIsInstance<X509TrustManager>().first().acceptedIssuers.take(2)
        assertEquals(2, roots.size)
        val bytes = AetherCaBundle.encode((roots + roots).map { it.encoded })
        val decoded = CertificateFactory.getInstance("X.509").generateCertificates(bytes.inputStream())
        assertEquals(2, decoded.size)
        assertEquals(bytes.toList(), AetherCaBundle.encode(roots.reversed().map { it.encoded }).toList())
    }

    @Test fun `missing or oversized trust roots fail closed`() {
        assertThrows(IllegalArgumentException::class.java) { AetherCaBundle.encode(emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { AetherCaBundle.encode(listOf(ByteArray(5 * 1024 * 1024))) }
    }
}

package dev.nirang.client.cores.aether

import java.util.Base64

/** PEM input works across Android legacy subject-hash directories and BoringSSL versions. */
internal object AetherCaBundle {
    fun encode(certificates: List<ByteArray>): ByteArray {
        require(certificates.isNotEmpty() && certificates.size <= 1024) { "Platform trust roots are unavailable" }
        require(certificates.sumOf { it.size.toLong() } <= 4 * 1024 * 1024) { "Platform trust roots are too large" }
        val encoder = Base64.getMimeEncoder(64, byteArrayOf(10))
        return certificates.map { encoder.encodeToString(it) }.distinct().sorted().joinToString("") {
            "-----BEGIN CERTIFICATE-----\n$it\n-----END CERTIFICATE-----\n"
        }.toByteArray(Charsets.US_ASCII)
    }
}

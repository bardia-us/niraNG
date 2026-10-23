package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord

/** Whole-certificate SHA256 constraints understood by the bundled Xray core. */
object TlsCertificatePolicy {
    private val pinKeys = setOf("pcs", "pinSHA256")

    fun normalizeOption(key: String, value: String): String = when (key) {
        in pinKeys -> value.split(',').map { part ->
            val pin = part.trim()
            require(Regex("^[0-9a-fA-F]{64}$").matches(pin) ||
                Regex("^(?:[0-9a-fA-F]{2}:){31}[0-9a-fA-F]{2}$").matches(pin)) {
                "TLS certificate pin must be a SHA256 certificate hash in hex"
            }
            pin.replace(":", "").lowercase()
        }.toSortedSet().joinToString(",")
        "vcn" -> value.split(',').map(String::trim).also { names ->
            require(names.all(String::isNotEmpty)) { "TLS verification names must not be empty" }
        }.joinToString(",")
        else -> value
    }

    fun fields(server: ServerRecord): Map<String, String> {
        val pins = pinKeys.mapNotNull { server.parameters[it]?.let { raw -> normalizeOption(it, raw) } }
        require(pins.distinct().size <= 1) { "Conflicting TLS certificate pin aliases" }
        val fields = buildMap {
            pins.firstOrNull()?.let { put("pinnedPeerCertSha256", it) }
            server.parameters["vcn"]?.let { put("verifyPeerCertByName", normalizeOption("vcn", it)) }
        }
        require(fields.isEmpty() || server.security.equals("tls", true)) {
            "Certificate constraints require TLS security"
        }
        return fields
    }

    fun isConstraint(key: String): Boolean = key in pinKeys || key == "vcn"
}

package dev.nirang.client.cores.aether

import java.io.File
import java.net.InetAddress
import org.json.JSONObject

/** Deliberately finite public settings. Private files, executable flags and TLS policy are app-owned. */
class AetherOptions private constructor(
    val mode: String,
    val psiphon: String,
    val psiphonMode: String,
    val psiphonRegion: String,
    val scan: String,
    val carrier: String,
    val ipFamily: String,
    val endpoint: String?,
    val outerEndpoint: String?,
    val innerEndpoint: String?,
    val fingerprint: String,
    val keepalive: Int,
    val dns: String,
    val startupTimeoutSeconds: Int,
) {
    val registerMode: String get() = when (mode) {
        "wireguard" -> "wg"
        "wireguard-over-masque" -> "gool"
        "warp-in-warp" -> "gool-classic"
        "masque-in-masque" -> "mim"
        else -> "masque"
    }

    val identityFiles: List<String> get() = if (psiphon == "only") emptyList() else when (mode) {
        "wireguard" -> listOf("aether-wg.toml")
        "wireguard-over-masque" -> listOf("aether-masque.toml", "aether-masque-gool.toml")
        "warp-in-warp" -> listOf("aether-wg.toml", "aether-wg-secondary.toml")
        "masque-in-masque" -> listOf("aether-masque.toml", "aether-masque-secondary.toml")
        else -> listOf("aether-masque.toml")
    }

    val overMasque: Boolean get() = mode !in setOf("wireguard", "warp-in-warp")

    fun outputPort(socksPort: Int, psiphonPort: Int): Int = if (psiphon == "chain") psiphonPort else socksPort

    fun arguments(privateDirectory: File, socksPort: Int, psiphonPort: Int, upstreamPort: Int,
                  registerOnly: Boolean = false, rescan: Boolean = false): List<String> {
        require(listOf(socksPort, psiphonPort).all { it in 1024..65535 })
        require(upstreamPort == 0 || upstreamPort in 1024..65535)
        require(setOf(socksPort, psiphonPort, upstreamPort).size == 3)
        return buildList {
            add(when (mode) { "wireguard" -> "--wg"; "wireguard-over-masque" -> "--gool"; "warp-in-warp" -> "--gool-classic"; "masque-in-masque" -> "--mim"; else -> "--masque" })
            addAll(listOf("--bind", "127.0.0.1:$socksPort",
                "--masque-config", File(privateDirectory, "aether-masque.toml").absolutePath,
                "--wg-config", File(privateDirectory, "aether-wg.toml").absolutePath,
                "--config", File(privateDirectory, "aether.toml").absolutePath,
                "--tls-verify", "--ip", ipFamily, "--scan", scan, "--dns", dns,
                "--keepalive", keepalive.toString(), "--log-level", "info"))
            addAll(listOf("--psiphon-mode", psiphonMode))
            if (psiphonRegion != "auto") addAll(listOf("--psiphon-region", psiphonRegion))
            if (upstreamPort != 0) addAll(listOf("--upstream", "socks5://127.0.0.1:$upstreamPort"))
            if (overMasque && carrier == "h2") add("--h2")
            if (overMasque) addAll(AetherFingerprints.profiles.getValue(fingerprint))
            if (mode in setOf("warp-in-warp", "masque-in-masque")) {
                val prefix = if (mode == "warp-in-warp") "--wiw" else "--mim"
                if (outerEndpoint == null && innerEndpoint == null || rescan) add("$prefix-scan")
                else {
                    outerEndpoint?.let { addAll(listOf("$prefix-outer", it)) }
                    innerEndpoint?.let { addAll(listOf("$prefix-inner", it)) }
                }
            } else {
                (outerEndpoint ?: endpoint)?.takeUnless { rescan }?.let { addAll(listOf("--peer",it)) }
                if (mode == "wireguard-over-masque") innerEndpoint?.let { addAll(listOf("--gool-peer",it)) }
            }
            add(if (rescan) "--no-quick-reconnect" else "--quick-reconnect")
            if (registerOnly) {
                addAll(listOf("--register", registerMode))
            } else when (psiphon) {
                "chain" -> addAll(listOf("--psiphon", "--psiphon-bind", "127.0.0.1:$psiphonPort"))
                "reverse" -> addAll(listOf("--psiphon-reverse", "--psiphon-bind", "127.0.0.1:$psiphonPort"))
                "only" -> add("--psiphon-only")
            }
        }
    }

    companion object {
        private val KEYS = setOf("mode", "psiphon", "psiphonMode", "psiphonRegion", "scan", "carrier", "ipFamily", "endpoint", "keepalive", "dns", "startupTimeoutSeconds", "outerEndpoint", "innerEndpoint", "fingerprint", "endpointHistory")

        fun parse(text: String): AetherOptions {
            require(text.toByteArray(Charsets.UTF_8).size <= 8192) { "Aether settings are too large" }
            val json = try { JSONObject(text) } catch (_: Exception) { throw IllegalArgumentException("Invalid Aether settings") }
            require(json.keys().asSequence().all { it in KEYS }) { "Unsupported Aether setting" }
            fun string(key: String, default: String): String {
                if (!json.has(key)) return default
                return (json.get(key) as? String) ?: throw IllegalArgumentException("Aether $key must be text")
            }
            fun choice(key: String, default: String, choices: Set<String>): String = string(key, default).also {
                require(it in choices) { "Unsupported Aether $key" }
            }
            fun integer(key: String, default: Int, range: IntRange): Int {
                if (!json.has(key)) return default
                val raw = json.get(key)
                require(raw is Int || raw is Long) { "Aether $key must be an integer" }
                val number = (raw as Number).toLong()
                require(number in range.first.toLong()..range.last.toLong()) { "Aether $key is out of range" }
                return number.toInt()
            }
            val mode = choice("mode", "masque", setOf("masque", "wireguard", "wireguard-over-masque", "warp-in-warp", "masque-in-masque"))
            val psiphon = choice("psiphon", "off", setOf("off", "chain", "reverse", "only"))
            val carrier = choice("carrier", "h3", setOf("h3", "h2"))
            require(mode !in setOf("wireguard", "warp-in-warp") || psiphon != "reverse") { "WireGuard cannot run over the TCP Psiphon proxy" }
            require(mode !in setOf("wireguard", "warp-in-warp") || carrier == "h3") { "HTTP/2 is a MASQUE carrier" }
            val endpoint = if (json.has("endpoint")) string("endpoint", "").takeIf { it.isNotEmpty() }?.also(::checkEndpoint) else null
            val outer = if (json.has("outerEndpoint")) string("outerEndpoint", "").takeIf { it.isNotEmpty() }?.also(::checkEndpoint) else null
            val inner = if (json.has("innerEndpoint")) string("innerEndpoint", "").takeIf { it.isNotEmpty() }?.also(::checkEndpoint) else null
            require(mode in setOf("wireguard-over-masque","warp-in-warp","masque-in-masque") || (outer == null && inner == null)) { "Hop endpoints require a nested mode" }
            if (mode in setOf("warp-in-warp","masque-in-masque") && outer != null && inner != null) require(outer.substringBeforeLast(':') != inner.substringBeforeLast(':')) { "Hop endpoints must differ" }
            val fingerprint=choice("fingerprint","native",AetherFingerprints.profiles.keys)
            require(mode !in setOf("wireguard","warp-in-warp") || fingerprint == "native") { "TLS fingerprint requires MASQUE" }
            if (json.has("endpointHistory")) {
                val history=json.get("endpointHistory") as? JSONObject ?: error("Invalid endpoint history")
                require(history.length() <= 5)
                history.keys().forEach { key ->
                    require(key in setOf("masque","wireguard","wireguard-over-masque","warp-in-warp","masque-in-masque"))
                    val item=history.get(key) as? JSONObject ?: error("Invalid endpoint history entry")
                    require(item.keys().asSequence().all { it in setOf("endpoint","outerEndpoint","innerEndpoint") })
                    val candidate=JSONObject(item.toString()).put("mode",key)
                    parse(candidate.toString())
                }
            }
            return AetherOptions(mode, psiphon, choice("psiphonMode", "auto", setOf("auto", "cdn", "direct")),
                choice("psiphonRegion", "auto", PsiphonRegions.codes),
                choice("scan", "balanced", setOf("turbo", "balanced", "stealth", "ironclad")), carrier,
                choice("ipFamily", "v4", setOf("v4", "v6", "both")), endpoint, outer, inner, fingerprint,
                integer("keepalive", 5, 5..120), choice("dns", "1.1.1.1", setOf("1.1.1.1", "1.0.0.1")),
                integer("startupTimeoutSeconds", 180, 30..300))
        }

        private fun checkEndpoint(value: String) {
            require(value.length in 7..80 && value.none { it.isWhitespace() }) { "Invalid Aether endpoint" }
            val host = if (value.startsWith('[')) value.substringBefore(']').removePrefix("[") else value.substringBeforeLast(':')
            val port = value.substringAfterLast(':').toIntOrNull()
            require(port != null && port in 1..65535 && (host.matches(Regex("[0-9.]+")) || host.matches(Regex("[0-9a-fA-F:]+")))) { "Aether endpoint must be a literal IP and port" }
            val address = try { InetAddress.getByName(host).address } catch (_: Exception) { throw IllegalArgumentException("Invalid Aether endpoint") }
            val cloudflare = if (address.size == 4) {
                require(host.split('.').size == 4 && !value.startsWith('[')) { "Invalid IPv4 endpoint" }
                val a=address[0].toInt() and 255
                val b=address[1].toInt() and 255
                val c=address[2].toInt() and 255
                (a == 162 && b == 159 && (c in 192..207 || c == 36 || c == 46)) ||
                    (a == 188 && b == 114 && c in 96..99)
            } else {
                require(value.startsWith('[') && value.contains("]:")) { "IPv6 endpoint needs brackets" }
                host.lowercase().startsWith("2606:4700:") && (address[4].toInt() and 255 == 1 && address[5].toInt() and 255 in 0..3 ||
                    address[4].toInt() == 0 && address[5].toInt() and 255 in 0xd0..0xd1)
            }
            require(cloudflare) { "Aether endpoint must be a supported Cloudflare WARP edge" }
        }
    }
}

package dev.nirang.client.xray

import android.content.Context
import java.net.Inet6Address
import java.net.InetAddress

object IranCidrRepository {
    @Volatile
    private var cached: List<String>? = null

    fun load(context: Context): List<String> = cached ?: synchronized(this) {
        cached ?: listOf(IPV4_ASSET, IPV6_ASSET)
            .flatMap { asset ->
                context.assets.open(asset).bufferedReader().useLines(::parse)
            }
            .also { require(it.isNotEmpty()) { "Iran CIDR assets are empty" } }
            .toList()
            .also { cached = it }
    }

    internal fun parse(lines: Sequence<String>): List<String> = lines
        .map(String::trim)
        .filter { it.isNotEmpty() && !it.startsWith('#') }
        .onEach { require(validCidr(it)) { "Invalid Iran CIDR asset entry" } }
        .distinct()
        .toList()

    private const val IPV4_ASSET = "routing/iran_ipv4.txt"
    private const val IPV6_ASSET = "routing/iran_ipv6.txt"
    private fun validCidr(value: String): Boolean {
        val parts = value.split('/', limit = 2)
        if (parts.size != 2) return false
        val prefix = parts[1].toIntOrNull() ?: return false
        val ipv4 = parts[0].split('.').let { octets ->
            octets.size == 4 && octets.all { it.toIntOrNull() in 0..255 }
        }
        if (ipv4) return prefix in 0..32
        val ipv6 = parts[0].contains(':') && runCatching {
            InetAddress.getByName(parts[0]) is Inet6Address
        }.getOrDefault(false)
        return ipv6 && prefix in 0..128
    }
}

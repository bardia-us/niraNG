package dev.nirang.client.network

import dev.nirang.client.xray.XrayConfigBuilder
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL

object ProxyIpChecker {
    fun check(providerUrl: String): Pair<String?, String?> {
        val proxy = Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", XrayConfigBuilder.LOCAL_HTTP_PROXY_PORT))
        val connection = URL(providerUrl).openConnection(proxy) as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 10_000
        connection.setRequestProperty("User-Agent", "niraNG/1.0")
        return try {
            if (connection.responseCode !in 200..299) return null to null
            val body = connection.inputStream.bufferedReader().use { it.readText() }.take(32_000).trim()
            if (body.startsWith("{")) {
                val json = JSONObject(body)
                val ip = json.optString("ip").ifBlank { json.optString("query") }.ifBlank { null }
                val country = json.optString("country").ifBlank { json.optString("country_code") }.ifBlank { null }
                ip to country
            } else {
                body.takeIf { it.matches(Regex("[0-9a-fA-F:.]+")) } to null
            }
        } finally {
            connection.disconnect()
        }
    }
}

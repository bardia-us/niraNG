package dev.nirang.client.network

import dev.nirang.client.xray.XrayConfigBuilder
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL

object ProxyIpChecker {
    data class Result(val ip: String?, val countryCode: String?, val city: String?)

    fun check(providerUrl: String): Result {
        val proxy = Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", XrayConfigBuilder.LOCAL_HTTP_PROXY_PORT))
        val connection = URL(providerUrl).openConnection(proxy) as HttpURLConnection
        connection.connectTimeout = 4_000
        connection.readTimeout = 5_000
            connection.setRequestProperty("User-Agent", "niraNG/1.1.1")
        return try {
            if (connection.responseCode !in 200..299) return Result(null, null, null)
            val body = connection.inputStream.bufferedReader().use { it.readText() }.take(32_000).trim()
            parseResponse(body)
        } finally {
            connection.disconnect()
        }
    }

    internal fun parseResponse(body: String): Result {
        if (!body.startsWith("{")) {
            return Result(body.takeIf { it.matches(Regex("[0-9a-fA-F:.]+")) }, null, null)
        }
        val json = JSONObject(body)
        val ip = json.cleanString("ip") ?: json.cleanString("query")
        val explicitCode = json.cleanString("country_code") ?: json.cleanString("countryCode")
        val countryCode = (explicitCode ?: json.cleanString("country")?.takeIf { it.length == 2 })
            ?.uppercase()
        return Result(ip, countryCode, json.cleanString("city"))
    }

    private fun JSONObject.cleanString(key: String): String? =
        optString(key).trim().takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
}

package dev.nirang.client.ping

import dev.nirang.client.cores.singbox.SingBoxConfigPolicy
import dev.nirang.client.subscription.CustomXrayConfig
import org.json.JSONArray
import org.json.JSONObject

/** Ephemeral input plumbing only. Stored JSON and outbound/DNS/routing policies are retained. */
internal object CustomProbeConfig {
    fun xray(raw: String, port: Int): String {
        val root = JSONObject(CustomXrayConfig.prepare(raw, true))
        val inputs = root.getJSONArray("inbounds")
        val tun = (0 until inputs.length()).map { inputs.getJSONObject(it) }.first { it.optString("protocol") == "tun" }
        val probe = JSONObject().put("protocol","socks").put("tag",tun.optString("tag").ifEmpty { "nirang-probe-tun" })
            .put("listen","127.0.0.1").put("port",port)
            .put("settings",JSONObject().put("auth","noauth").put("udp",false))
        tun.optJSONObject("sniffing")?.let { probe.put("sniffing",it) }
        root.put("inbounds",JSONArray().put(probe))
        root.put("log",JSONObject().put("loglevel","none"))
        return root.toString()
    }

    fun singBox(raw: String, port: Int, privateCachePath: String? = null): String {
        SingBoxConfigPolicy.validate(raw)
        val root = JSONObject(raw)
        val inputs = root.getJSONArray("inbounds")
        val tun = (0 until inputs.length()).map { inputs.getJSONObject(it) }.first { it.optString("type") == "tun" }
        val probe = JSONObject().put("type","socks").put("listen","127.0.0.1").put("listen_port",port)
        tun.optString("tag").takeIf { it.isNotEmpty() }?.let { probe.put("tag",it) }
        root.put("inbounds",JSONArray().put(probe))
        root.put("log",JSONObject().put("disabled",true))
        // StartedService always opens a cache DB, even when cache_file.enabled=false.
        // Its path must belong to this probe, never the active core's default cache.db.
        if (privateCachePath != null) {
            val experimental = root.optJSONObject("experimental") ?: JSONObject().also { root.put("experimental",it) }
            val cache = experimental.optJSONObject("cache_file") ?: JSONObject().also { experimental.put("cache_file",it) }
            cache.put("path",privateCachePath)
        }
        return root.toString()
    }
}

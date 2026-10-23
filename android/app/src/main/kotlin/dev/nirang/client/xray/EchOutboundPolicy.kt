package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** Per-profile GUI option -> real Xray outbound + tlsSettings.echSockopt.
 * Never log this JSON: an auxiliary outbound may contain credentials. */
object EchOutboundPolicy {
    private val reserved = setOf("proxy", "direct", "blocked", "block", "dns-out")

    fun parse(raw: String): JSONObject {
        require(raw.length <= 32768) { "ECH outbound is too long" }
        val reader = JSONTokener(raw)
        val value = runCatching { reader.nextValue() }.getOrElse {
            throw IllegalArgumentException("ECH outbound must be a JSON object")
        }
        require(value is JSONObject && reader.nextClean() == '\u0000') { "ECH outbound must be one JSON object" }
        val tag = value.opt("tag")
        require(tag is String && tag.isNotBlank() && tag == tag.trim() && tag.length <= 128 &&
            tag !in reserved && !tag.startsWith("proxy", true)) { "ECH outbound needs a unique non-reserved tag" }
        require(value.opt("protocol") is String && value.getString("protocol").isNotBlank()) {
            "ECH outbound needs a protocol"
        }
        // A helper cannot dial the main proxy (which is waiting on its ECH
        // query), itself, or an undefined outbound. This app has one helper.
        fun checkReferences(node: Any?, depth: Int) {
            require(depth <= 24) { "ECH outbound is nested too deeply" }
            when (node) {
                is JSONObject -> node.keys().forEach { key ->
                    val child = node.get(key)
                    if (key == "dialerProxy" || (key == "tag" && node.has("transportLayer"))) {
                        require(child is String && (child.isEmpty() || child == "direct")) {
                            "ECH outbound has a recursive or undefined dialer"
                        }
                    }
                    require(key != "echOutbound") { "Nested ECH outbound is not supported" }
                    checkReferences(child, depth + 1)
                }
                is JSONArray -> for (index in 0 until node.length()) checkReferences(node.get(index), depth + 1)
            }
        }
        checkReferences(value, 0)
        value.optJSONObject("proxySettings")?.let {
            require(it.optString("tag").isBlank() || it.optString("tag") == "direct") {
                "ECH outbound has a recursive or undefined proxy"
            }
        }
        return value
    }

    fun validate(server: ServerRecord): JSONObject? {
        val raw = server.parameters["echOutbound"].orEmpty().trim()
        val ech = (server.parameters["echConfigList"]?.takeIf(String::isNotBlank)
            ?: server.parameters["ech"]).orEmpty().trim()
        if (raw.isEmpty()) {
            require(!ech.contains("h2c://", true)) { "h2c ECH requires an ECH outbound" }
            return null
        }
        require(server.security.equals("tls", true)) { "ECH outbound requires TLS" }
        require(ech.isNotEmpty()) { "ECH outbound requires echConfigList" }
        return parse(raw)
    }

    fun attach(config: JSONObject, server: ServerRecord) {
        val helper = validate(server) ?: return
        val outbounds = config.getJSONArray("outbounds")
        val tag = helper.getString("tag")
        for (index in 0 until outbounds.length()) {
            require(outbounds.getJSONObject(index).optString("tag") != tag) { "ECH outbound tag conflicts with another outbound" }
        }
        val tls = outbounds.getJSONObject(0).getJSONObject("streamSettings").getJSONObject("tlsSettings")
        tls.put("echSockopt", JSONObject().put("dialerProxy", tag))
        outbounds.put(helper)
    }
}

package dev.nirang.client.subscription

import org.json.JSONArray
import org.json.JSONObject

/** Full JSON keeps its DNS, routing and outbounds. Android input plumbing and
 * local inbound telemetry are supplied on this runtime copy only. */
internal object CustomXrayConfig {
    // Only callers holding an already prepared runtime copy use this limit.
    // Tagging each untagged inlet can grow the bounded original; the external
    // codec and prepare() keep their original 256 KiB source limit.
    fun prepareRuntime(raw: String, includeTun: Boolean): String =
        prepare(raw,includeTun,CustomProfileCodec.MAX_PAYLOAD_BYTES * 2 + 4096)

    fun trafficInboundTags(runtime: String, includeTun: Boolean): String? {
        val root=JSONObject(runtime)
        // Both local proxy inputs can be first entrances. If an outbound feeds
        // either of them again, summing their counters is no longer a lower
        // bound. Keep this unusual proxy-only topology unavailable; the TUN
        // entrance remains unambiguous for the same config in VPN mode.
        if (!includeTun && reentersProxyEntrance(root.optJSONArray("outbounds"),root.optJSONObject("dns")?.optJSONObject("hosts"))) return null
        val inputs=root.getJSONArray("inbounds")
        return JSONArray().apply {
            for(index in 0 until inputs.length()) {
                val input=inputs.getJSONObject(index)
                if (if(includeTun) input.optString("protocol") == "tun"
                    else input.optInt("port") in setOf(10808,10809)) put(input.getString("tag"))
            }
            check(length() > 0) { "No Android traffic entrance" }
        }.toString()
    }

    private fun reentersProxyEntrance(node: Any?, hosts: JSONObject?): Boolean = when(node) {
        is JSONObject -> {
            val redirect=if(node.optString("protocol") in setOf("freedom","direct"))
                node.optJSONObject("settings")?.optString("redirect").orEmpty() else ""
            isProxyEntrance(node.optString("address"),node.optInt("port"),hosts) ||
                isProxyEntrance(redirect.substringBeforeLast(':').removeSurrounding("[","]"),redirect.substringAfterLast(':').toIntOrNull() ?: 0,hosts) ||
                node.keys().asSequence().any { reentersProxyEntrance(node.opt(it),hosts) }
        }
        is JSONArray -> (0 until node.length()).any { reentersProxyEntrance(node.opt(it),hosts) }
        else -> false
    }

    private fun isProxyEntrance(address: String, port: Int, hosts: JSONObject?): Boolean =
        port in setOf(10808,10809) && knownLoopbackAddress(address,hosts,hashSetOf())

    private fun knownLoopbackAddress(address: String, hosts: JSONObject?, visited: MutableSet<String>): Boolean {
        val name=address.lowercase().trimEnd('.')
        if (name in setOf("127.0.0.1","::1","localhost","::ffff:127.0.0.1")) return true
        if (hosts == null || !visited.add(name)) return false
        // Resolve only the explicit static forms we can prove here. This does
        // not run DNS or change the user's DNS/route configuration.
        return hosts.keys().asSequence().any { key ->
            val rule=key.lowercase().trimEnd('.')
            val matches=when {
                rule.startsWith("full:") -> name == rule.removePrefix("full:")
                rule.startsWith("domain:") -> rule.removePrefix("domain:").let { name == it || name.endsWith(".$it") }
                else -> name == rule
            }
            if (!matches) false else when(val value=hosts.opt(key)) {
                is String -> knownLoopbackAddress(value,hosts,visited)
                is JSONArray -> (0 until value.length()).any { index ->
                    (value.opt(index) as? String)?.let { knownLoopbackAddress(it,hosts,visited) } == true
                }
                else -> false
            }
        }
    }

    fun prepare(raw: String, includeTun: Boolean): String = prepare(raw,includeTun,CustomProfileCodec.MAX_PAYLOAD_BYTES)

    private fun prepare(raw: String, includeTun: Boolean, maxBytes: Int): String {
        val root = StrictProfileJson.objectValue(raw, maxBytes)
        require(CustomProfileCodec.detectEngine(root) == "xray") { "Custom config is not Xray" }
        require(!root.has("api")) { "Custom Xray control APIs are not available on Android" }
        checkFileAccess(root)
        root.optJSONObject("log")?.let { log ->
            for (key in listOf("access","error")) require(log.optString(key) in setOf("","none")) { "Custom log files are not available on Android" }
        }
        val inputs = root.optJSONArray("inbounds") ?: JSONArray().also { require(!root.has("inbounds")) { "Invalid custom inbounds" } }
        var tunCount = 0
        val tags = hashSetOf<String>()
        for (i in 0 until inputs.length()) {
            val input = inputs.getJSONObject(i)
            val protocol = input.optString("protocol")
            input.optString("tag").takeIf(String::isNotEmpty)?.let { require(tags.add(it)) { "Duplicate custom inbound tag" } }
            if (protocol == "tun") {
                tunCount++
                require(includeTun && tunCount == 1) { "Custom config requires exactly one Android TUN" }
                val settings = input.optJSONObject("settings") ?: JSONObject().also { require(!input.has("settings")) { "Invalid TUN settings" };input.put("settings",it) }
                settings.put("name","xray0")
                val mtu = settings.optInt("mtu",1500)
                require(mtu in 1280..1500) { "Unsupported custom Android TUN MTU" }
            } else {
                require(input.opt("listen") is String && input.getString("listen") in setOf("127.0.0.1","::1")) { "Custom listeners must bind a loopback IP explicitly" }
                require(input.opt("port") is Number && input.optInt("port") in 1..65535) { "Custom listener port is invalid" }
            }
        }
        if (includeTun && tunCount == 0) {
            require(tags.add("nirang-custom-tun")) { "Reserved Android input tag is already used" }
            inputs.put(JSONObject().put("tag","nirang-custom-tun").put("protocol","tun").put("port",0)
                .put("settings",JSONObject().put("name","xray0").put("mtu",1500)))
        }
        fun localInput(protocol: String, port: Int) {
            val matches = (0 until inputs.length()).map { inputs.getJSONObject(it) }.filter { it.optInt("port") == port }
            if (matches.isNotEmpty()) {
                require(matches.size == 1 && matches.single().optString("protocol") == protocol) { "Custom input conflicts with Android local proxy" }
                val settings = matches.single().optJSONObject("settings")
                require(settings?.optString("auth").orEmpty() in setOf("","noauth") && (settings?.optJSONArray("accounts")?.length() ?: 0) == 0) { "Android local proxy input must not require authentication" }
                return
            }
            val tag = "nirang-custom-$protocol"
            require(tags.add(tag)) { "Reserved Android input tag is already used" }
            inputs.put(JSONObject().put("tag",tag).put("protocol",protocol).put("listen","127.0.0.1").put("port",port)
                .put("settings",JSONObject().apply { if (protocol == "socks") { put("auth","noauth");put("udp",true) } }))
        }
        localInput("socks",10808)
        localInput("http",10809)
        // An inlet is the accounting boundary: summing arbitrary outbound tags
        // counts a chained outbound's bytes more than once. Untagged inputs do
        // not register Xray counters, so give only those inputs unused tags.
        val meterTags = tags.toMutableSet()
        root.optJSONObject("routing")?.optJSONArray("rules")?.let { rules ->
            for (index in 0 until rules.length()) {
                // The pinned core's StringList also accepts a comma-separated
                // string. Reserve both forms without normalizing the user's rule.
                when (val references = rules.optJSONObject(index)?.opt("inboundTag")) {
                    is JSONArray -> for (ref in 0 until references.length())
                        (references.opt(ref) as? String)?.let(meterTags::add)
                    is String -> meterTags.addAll(references.split(','))
                }
            }
        }
        var meterIndex = 0
        for (index in 0 until inputs.length()) {
            val input = inputs.getJSONObject(index)
            if (input.optString("tag").isEmpty()) {
                var tag: String
                do { tag = "nirang-meter-${++meterIndex}" } while (!meterTags.add(tag))
                input.put("tag",tag)
            }
        }
        root.put("inbounds",inputs)
        root.optJSONObject("stats") ?: JSONObject().also {
            require(!root.has("stats") || root.isNull("stats")) { "Invalid custom stats" }
            root.put("stats",it)
        }
        val policy = root.optJSONObject("policy") ?: JSONObject().also {
            require(!root.has("policy") || root.isNull("policy")) { "Invalid custom policy" }
            root.put("policy",it)
        }
        val system = policy.optJSONObject("system") ?: JSONObject().also {
            require(!policy.has("system") || policy.isNull("system")) { "Invalid custom system policy" }
            policy.put("system",it)
        }
        system.put("statsInboundUplink",true).put("statsInboundDownlink",true)
        return root.toString()
    }

    private fun checkFileAccess(node: Any?) {
        when (node) {
            is JSONObject -> node.keys().forEach { key ->
                val normalized = key.lowercase().replace("_", "")
                require(normalized !in setOf("certificatefile","keyfile","secretfile","keylog","keylogfile","masterkeylog","configfile","assetdirectory","geodatadir")) { "Custom profile local file access is not permitted" }
                val value = node.opt(key)
                if (value is String) require(!value.startsWith("file:", true) && !value.startsWith("ext:", true) && !value.startsWith("ext-ip:",true)) { "Custom profile local file access is not permitted" }
                checkFileAccess(value)
            }
            is JSONArray -> for (i in 0 until node.length()) checkFileAccess(node.opt(i))
        }
    }
}

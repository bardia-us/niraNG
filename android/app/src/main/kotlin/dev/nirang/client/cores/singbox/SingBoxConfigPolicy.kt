package dev.nirang.client.cores.singbox

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** Android-specific checks run before native validation can open files or listeners. */
internal object SingBoxConfigPolicy {
    const val VERSION = "1.14.4"
    private val bypassProtect = setOf("bind_interface", "inet4_bind_address", "inet6_bind_address", "protect_path", "default_interface", "netns")
    private val fileFields = setOf("path", "directory", "file", "dhcp_lease_files", "command", "args", "environ", "environment")
    private val unsupportedTun = setOf("interface_name", "include_interface", "exclude_interface", "include_uid", "exclude_uid", "include_uid_range", "exclude_uid_range", "include_android_user", "include_mac_address", "exclude_mac_address", "platform", "loopback_address", "route_address_set", "route_exclude_address_set")

    fun validate(config: String) {
        require(config.toByteArray(Charsets.UTF_8).size <= 256 * 1024) { "sing-box JSON is too large" }
        checkDepth(config)
        val root = try {
            val tokener = JSONTokener(config)
            val result = tokener.nextValue()
            require(result is JSONObject && tokener.nextClean() == '\u0000')
            result
        } catch (_: Exception) {
            throw IllegalArgumentException("sing-box requires one valid JSON object")
        }
        require(root.optJSONObject("route")?.opt("auto_detect_interface") == true) {
            "Android sing-box requires route.auto_detect_interface=true for protected sockets"
        }
        require(root.optJSONObject("route")?.optBoolean("override_android_vpn", false) != true) {
            "Android sing-box cannot use its own VPN as upstream"
        }
        for (key in listOf("services", "certificate_providers", "network_namespaces")) {
            require(!active(root.opt(key))) { "Android sing-box does not allow $key" }
        }
        val inbounds = root.optJSONArray("inbounds") ?: throw IllegalArgumentException("Android sing-box requires one TUN inbound")
        var tunnelCount = 0
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.getJSONObject(i)
            when (inbound.optString("type")) {
                "tun" -> {
                    tunnelCount++
                    require(inbound.opt("auto_route") == true) { "Android sing-box TUN requires explicit auto_route=true" }
                    require(active(inbound.opt("address"))) { "Android sing-box TUN requires explicit address" }
                    require(inbound.optBoolean("auto_redirect", false) != true) { "auto_redirect requires privileged Linux routing" }
                    for (key in unsupportedTun) require(!active(inbound.opt(key))) { "Android sing-box does not support TUN $key" }
                    require(!active(inbound.opt("include_package")) || !active(inbound.opt("exclude_package"))) { "TUN include_package and exclude_package cannot be combined" }
                }
                "socks", "http", "mixed" -> {
                    require(inbound.optString("listen") in setOf("127.0.0.1", "::1")) { "Android sing-box proxy inbounds must explicitly bind loopback" }
                    require(!inbound.optBoolean("set_system_proxy", false)) { "Android sing-box does not set a system proxy" }
                }
                else -> throw IllegalArgumentException("Unsupported Android sing-box inbound type")
            }
        }
        require(tunnelCount == 1) { "Android sing-box requires exactly one TUN inbound" }
        root.optJSONArray("endpoints")?.let { endpoints ->
            for (i in 0 until endpoints.length()) {
                val endpoint = endpoints.getJSONObject(i)
                require(endpoint.optString("type") == "wireguard" && !endpoint.optBoolean("system", false) && endpoint.optInt("listen_port", 0) == 0) {
                    "Android sing-box supports only userspace WireGuard client endpoints"
                }
            }
        }
        val experimental = root.optJSONObject("experimental")
        if (experimental != null) {
            for (key in listOf("clash_api", "v2ray_api", "debug")) require(!experimental.has(key)) { "Android sing-box does not expose $key" }
        }
        require(!active(root.optJSONObject("log")?.opt("output"))) { "Android sing-box does not allow log file output" }
        walk(root, "")
    }

    private fun walk(value: Any?, parent: String) {
        when (value) {
            is JSONObject -> {
                require(value.optString("type") != "tor") { "External Tor executables are disabled" }
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val child = value.opt(key)
                    if (active(child)) {
                        require(key !in bypassProtect) { "Android sing-box does not allow $key: socket protection must remain active" }
                        val networkPath = key == "path" && (parent == "transport" || value.optString("type") in setOf("http", "https", "h3", "httpupgrade", "ws"))
                        val matchOnly = key in setOf("process_path", "process_path_regex")
                        require(networkPath || matchOnly || (key !in fileFields && !key.endsWith("_path") && !key.endsWith("_file") && !key.endsWith("_directory"))) { "Android sing-box does not allow file or command option $key" }
                        require(key !in setOf("acme", "external_ui", "external_controller", "pre_shared_key_file", "ssh_host_key")) { "Android sing-box does not allow $key" }
                        require(key !in setOf("extra_args", "torrc", "wifi_ssid", "wifi_bssid")) { "Android sing-box does not support $key" }
                    }
                    walk(child, key)
                }
            }
            is JSONArray -> for (i in 0 until value.length()) walk(value.opt(i), parent)
        }
    }

    private fun active(value: Any?): Boolean = when (value) {
        null, JSONObject.NULL, false -> false
        is String -> value.isNotEmpty()
        is JSONArray -> value.length() > 0
        is JSONObject -> value.length() > 0
        else -> true
    }

    private fun checkDepth(config: String) {
        var depth = 0
        var quoted = false
        var escape = false
        for (char in config) {
            if (quoted) {
                if (escape) escape = false else if (char == '\\') escape = true else if (char == '"') quoted = false
            } else when (char) {
                '"' -> quoted = true
                '{', '[' -> { depth++; require(depth <= 64) { "sing-box JSON is too deeply nested" } }
                '}', ']' -> depth--
            }
        }
    }
}

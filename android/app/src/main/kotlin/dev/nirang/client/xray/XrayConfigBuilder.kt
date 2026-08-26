package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.settings.NativeSettings
import org.json.JSONArray
import org.json.JSONObject

object XrayConfigBuilder {
    const val DEFAULT_LOCAL_SOCKS_PORT = 10808
    const val LOCAL_HTTP_PROXY_PORT = 10809

    fun buildVpnConfig(server: ServerRecord, settings: NativeSettings): String =
        buildConfig(server, settings, includeTun = true)

    fun buildProxyConfig(server: ServerRecord, settings: NativeSettings): String =
        buildConfig(server, settings, includeTun = false)

    fun buildProbeConfig(server: ServerRecord, settings: NativeSettings): String =
        baseConfig(server, settings, includeTun = false)
            .apply {
                put("inbounds", JSONArray())
                remove("dns")
                remove("fakedns")
                put("routing", JSONObject().apply {
                    put("domainStrategy", "AsIs")
                    put("rules", JSONArray())
                })
            }
            .toString()
            .also(::validateGeneratedConfig)

    fun buildSafeFallbackConfig(server: ServerRecord): String =
        baseConfig(server, null, includeTun = true)
            .put("inbounds", buildInbounds(null, includeTun = true))
            .toString()
            .also(::validateGeneratedConfig)

    private fun buildConfig(
        server: ServerRecord,
        settings: NativeSettings,
        includeTun: Boolean,
    ): String = baseConfig(server, settings, includeTun)
        .put("inbounds", buildInbounds(settings, includeTun))
        .toString()
        .also(::validateGeneratedConfig)

    private fun baseConfig(
        server: ServerRecord,
        settings: NativeSettings?,
        includeTun: Boolean,
    ): JSONObject = JSONObject().apply {
        validateServer(server)
        put("log", JSONObject().apply { put("loglevel", "warning") })
        put("dns", buildDns(settings))
        if (settings?.enableLocalDns == true && settings.enableFakeDns) {
            put("fakedns", JSONArray().put(JSONObject().apply {
                put("ipPool", "198.18.0.0/15")
                put("poolSize", 65_535)
            }))
        }
        put("outbounds", JSONArray().apply {
            put(buildProxyOutbound(server, settings))
            put(JSONObject().apply {
                put("tag", "dns-out")
                put("protocol", "dns")
                put("settings", JSONObject().apply { put("nonIPQuery", "skip") })
            })
            put(JSONObject().apply {
                put("tag", "direct")
                put("protocol", "freedom")
                put("settings", JSONObject())
            })
            put(JSONObject().apply {
                put("tag", "blocked")
                put("protocol", "blackhole")
                put("settings", JSONObject())
            })
        })
        put("routing", buildRouting(settings, includeTun))
    }

    private fun buildInbounds(settings: NativeSettings?, includeTun: Boolean): JSONArray = JSONArray().apply {
        val fakeDns = settings?.enableLocalDns == true && settings.enableFakeDns
        val sniffingEnabled = settings?.sniffingEnabled ?: true
        val overrides = mutableListOf<String>()
        if (sniffingEnabled) overrides += listOf("http", "tls", "quic")
        if (fakeDns) overrides += "fakedns"
        val sniffing = JSONObject().apply {
            put("enabled", sniffingEnabled || fakeDns)
            put("destOverride", JSONArray(overrides))
            put("routeOnly", sniffingEnabled && (settings?.routeOnly ?: false))
        }
        if (includeTun) {
            put(JSONObject().apply {
                put("tag", "tun-in")
                put("port", 0)
                put("protocol", "tun")
                put("settings", JSONObject().apply { put("mtu", settings?.vpnMtu ?: 1500) })
                put("sniffing", sniffing)
            })
        }
        put(JSONObject().apply {
            put("tag", "local-socks")
            put("listen", "127.0.0.1")
            put("port", settings?.localSocksPort ?: DEFAULT_LOCAL_SOCKS_PORT)
            put("protocol", "socks")
            put("settings", JSONObject().apply {
                put("auth", "noauth")
                put("udp", true)
            })
            put("sniffing", sniffing)
        })
        put(JSONObject().apply {
            put("tag", "local-http")
            put("listen", "127.0.0.1")
            put("port", LOCAL_HTTP_PROXY_PORT)
            put("protocol", "http")
            put("settings", JSONObject().apply { put("allowTransparent", false) })
        })
    }

    private fun buildProxyOutbound(server: ServerRecord, settings: NativeSettings?): JSONObject = JSONObject().apply {
        put("tag", "proxy")
        put("protocol", server.protocol.lowercase())
        put("settings", when (server.protocol.lowercase()) {
            "trojan" -> JSONObject().apply {
                put("servers", JSONArray().apply {
                    put(JSONObject().apply {
                        put("address", server.address)
                        put("port", server.port)
                        put("password", server.credential)
                    })
                })
            }
            "vmess" -> JSONObject().apply {
                put("vnext", JSONArray().apply {
                    put(JSONObject().apply {
                        put("address", server.address)
                        put("port", server.port)
                        put("users", JSONArray().apply {
                            put(JSONObject().apply {
                                put("id", server.credential)
                                put("alterId", server.parameters["alterId"]?.toIntOrNull() ?: 0)
                                put("security", server.parameters["encryption"] ?: "auto")
                            })
                        })
                    })
                })
            }
            else -> JSONObject().apply {
                put("vnext", JSONArray().apply {
                    put(JSONObject().apply {
                        put("address", server.address)
                        put("port", server.port)
                        put("users", JSONArray().apply {
                            put(JSONObject().apply {
                                put("id", server.credential)
                                put("encryption", server.parameters["encryption"] ?: "none")
                                server.parameters["flow"]?.takeIf(String::isNotBlank)?.let { put("flow", it) }
                            })
                        })
                    })
                })
            }
        })
        put("streamSettings", buildStreamSettings(server, settings))
        put("mux", JSONObject().apply { put("enabled", false) })
    }

    private fun buildStreamSettings(server: ServerRecord, settings: NativeSettings?): JSONObject = JSONObject().apply {
        val network = when (server.transport.lowercase()) {
            "splithttp" -> "xhttp"
            else -> server.transport.lowercase()
        }
        put("network", network)
        put("security", server.security.lowercase().takeUnless { it.isBlank() } ?: "none")
        when (network) {
            "ws" -> put("wsSettings", JSONObject().apply {
                put("path", server.parameters["path"] ?: "/")
                server.parameters["host"]?.takeIf(String::isNotBlank)?.let {
                    put("headers", JSONObject().apply { put("Host", it) })
                }
            })
            "grpc" -> put("grpcSettings", JSONObject().apply {
                put("serviceName", server.parameters["serviceName"] ?: server.parameters["path"] ?: "")
                put("multiMode", server.parameters["mode"].equals("multi", true))
            })
            "xhttp" -> put("xhttpSettings", JSONObject().apply {
                put("path", server.parameters["path"] ?: "/")
                server.parameters["host"]?.takeIf(String::isNotBlank)?.let { put("host", it) }
                server.parameters["mode"]?.takeIf(String::isNotBlank)?.let { put("mode", it) }
            })
            "tcp" -> server.parameters["headerType"]?.takeIf { it != "none" && it.isNotBlank() }?.let { headerType ->
                put("tcpSettings", JSONObject().apply {
                    put("header", JSONObject().apply { put("type", headerType) })
                })
            }
        }
        when (server.security.lowercase()) {
            "tls" -> put("tlsSettings", JSONObject().apply {
                put("serverName", server.parameters["sni"] ?: server.parameters["host"] ?: server.address)
                putOptionalArray("alpn", server.parameters["alpn"])
                server.parameters["fp"]?.takeIf(String::isNotBlank)?.let { put("fingerprint", it) }
            })
            "reality" -> put("realitySettings", JSONObject().apply {
                put("serverName", server.parameters["sni"] ?: server.address)
                put("fingerprint", server.parameters["fp"] ?: "chrome")
                put("publicKey", server.parameters["pbk"] ?: "")
                put("shortId", server.parameters["sid"] ?: "")
                put("spiderX", server.parameters["spx"] ?: "/")
            })
        }
        if (settings?.enableIpv6 == true && settings.preferIpv6) {
            put(
                "sockopt",
                JSONObject().apply { put("domainStrategy", "UseIPv6v4") },
            )
        }
    }

    private fun buildDns(settings: NativeSettings?): JSONObject = JSONObject().apply {
        val servers = settings?.remoteDns
            ?.let(::splitRules)
            ?.distinct()
            .orEmpty()
            .ifEmpty { listOf("localhost") }
            .toMutableList()
        if (settings?.enableLocalDns == true && settings.enableFakeDns) servers.add(0, "fakedns")
        put("servers", JSONArray(servers))
        put("queryStrategy", if (settings?.enableIpv6 == true) "UseIP" else "UseIPv4")
    }

    private fun buildRouting(settings: NativeSettings?, includeTun: Boolean): JSONObject = JSONObject().apply {
        put("domainStrategy", settings?.domainStrategy ?: "IPIfNonMatch")
        put("rules", JSONArray().apply {
            if (settings?.enableLocalDns != false) {
                put(JSONObject().apply {
                    put("type", "field")
                    put(
                        "inboundTag",
                        JSONArray(if (includeTun) listOf("tun-in") else listOf("local-socks", "local-http")),
                    )
                    put("network", "tcp,udp")
                    put("port", "53")
                    put("outboundTag", "dns-out")
                })
            }
            val privateIps = listOf("geoip:private")
            // geoip:private is built into Xray. There is no guaranteed
            // geosite:private tag, so LAN hostnames use data-file-free matchers.
            val privateDomains = listOf("full:localhost", "domain:localhost", "domain:local")
            val customIps = splitRules(settings?.customIps.orEmpty())
            val customDomains = splitRules(settings?.customDomains.orEmpty())
            when (settings?.routingMode ?: "global") {
                "bypassLan" -> putRoutingRule("direct", privateIps, privateDomains)
                "custom" -> {
                    putRoutingRule("direct", privateIps, privateDomains)
                    putRoutingRule("direct", customIps, customDomains)
                }
            }
        })
    }

    fun validateGeneratedConfig(config: String) {
        val root = runCatching { JSONObject(config) }
            .getOrElse { throw IllegalArgumentException("Generated Xray JSON is invalid", it) }
        val outbounds = root.optJSONArray("outbounds") ?: error("Generated Xray config has no outbounds")
        val outboundTags = buildSet {
            for (index in 0 until outbounds.length()) {
                outbounds.optJSONObject(index)?.optString("tag")?.takeIf(String::isNotBlank)?.let(::add)
            }
        }
        require("proxy" in outboundTags && "direct" in outboundTags) { "Generated Xray outbounds are incomplete" }
        val rules = root.optJSONObject("routing")?.optJSONArray("rules")
            ?: error("Generated Xray routing rules are missing")
        for (index in 0 until rules.length()) {
            val rule = rules.optJSONObject(index) ?: error("Generated Xray routing rule is invalid")
            val outbound = rule.optString("outboundTag")
            require(outbound in outboundTags) { "Generated Xray routing rule has an unknown outbound" }
            rule.optJSONArray("domain")?.let { domains ->
                for (domainIndex in 0 until domains.length()) {
                    val domain = domains.optString(domainIndex)
                    require(domain.isNotBlank() && !domain.startsWith("geosite:", true)) {
                        "Generated Xray domain rule requires unavailable geosite data"
                    }
                }
            }
            rule.optJSONArray("ip")?.let { ips ->
                for (ipIndex in 0 until ips.length()) {
                    val ip = ips.optString(ipIndex)
                    require(!ip.startsWith("geoip:", true) || ip.equals("geoip:private", true)) {
                        "Generated Xray IP rule requires unavailable geoip data"
                    }
                }
            }
        }
    }

    private fun validateServer(server: ServerRecord) {
        require(server.protocol.lowercase() in setOf("vless", "vmess", "trojan")) { "Unsupported proxy protocol" }
        require(server.address.isNotBlank() && server.address.length <= 253) { "Server address is invalid" }
        require(server.port in 1..65_535) { "Server port is invalid" }
        require(server.credential.isNotBlank()) { "Server credential is missing" }
        require(server.security.lowercase() in setOf("", "none", "tls", "reality")) { "Unsupported transport security" }
        if (server.security.equals("reality", true)) {
            require(!server.parameters["pbk"].isNullOrBlank()) { "Reality public key is missing" }
        }
    }

    private fun JSONArray.putRoutingRule(
        outboundTag: String,
        ips: List<String>,
        domains: List<String>,
    ) {
        if (ips.isEmpty() && domains.isEmpty()) return
        put(JSONObject().apply {
            put("type", "field")
            if (ips.isNotEmpty()) put("ip", JSONArray(ips))
            if (domains.isNotEmpty()) put("domain", JSONArray(domains))
            put("outboundTag", outboundTag)
        })
    }

    private fun splitRules(value: String): List<String> = value
        .split(',', '\n')
        .map(String::trim)
        .filter(String::isNotEmpty)

    private fun JSONObject.putOptionalArray(key: String, csv: String?) {
        val values = csv?.split(',')?.map(String::trim)?.filter(String::isNotEmpty).orEmpty()
        if (values.isNotEmpty()) put(key, JSONArray(values))
    }
}

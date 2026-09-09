package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import dev.nirang.client.settings.NativeSettings
import org.json.JSONArray
import org.json.JSONObject

object XrayConfigBuilder {
    const val DEFAULT_LOCAL_SOCKS_PORT = 10808
    const val LOCAL_HTTP_PROXY_PORT = 10809
    internal const val ANDROID_TUN_CONFIG_NAME = "xray0"

    fun buildVpnConfig(
        server: ServerRecord,
        settings: NativeSettings,
        iranCidrs: List<String> = emptyList(),
    ): String = buildConfig(server, settings, includeTun = true, iranCidrs = iranCidrs)

    fun buildProxyConfig(
        server: ServerRecord,
        settings: NativeSettings,
        iranCidrs: List<String> = emptyList(),
    ): String = buildConfig(server, settings, includeTun = false, iranCidrs = iranCidrs)

    fun buildProbeConfig(server: ServerRecord, settings: NativeSettings): String =
        baseConfig(
            server,
            settings,
            includeTun = false,
            iranCidrs = emptyList(),
            routingModeOverride = "global",
        )
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
        baseConfig(server, null, includeTun = true, iranCidrs = emptyList())
            .put("inbounds", buildInbounds(null, includeTun = true))
            .toString()
            .also(::validateGeneratedConfig)

    private fun buildConfig(
        server: ServerRecord,
        settings: NativeSettings,
        includeTun: Boolean,
        iranCidrs: List<String>,
    ): String = baseConfig(server, settings, includeTun, iranCidrs)
        .put("inbounds", buildInbounds(settings, includeTun))
        .toString()
        .also(::validateGeneratedConfig)

    private fun baseConfig(
        server: ServerRecord,
        settings: NativeSettings?,
        includeTun: Boolean,
        iranCidrs: List<String>,
        routingModeOverride: String? = null,
    ): JSONObject = JSONObject().apply {
        validateServer(server)
        put("log", JSONObject().apply { put("loglevel", "warning") })
        put("dns", buildDns(settings))
        if (settings?.observatoryEnabled == true) {
            val sections = buildObservatorySections(
                settings.leastPingInterval,
                settings.leastLoadInterval,
                settings.leastLoadHttpMethod,
                settings.leastLoadSampling,
                settings.leastLoadTimeout,
            )
            put("observatory", sections.getJSONObject("observatory"))
            put("burstObservatory", sections.getJSONObject("burstObservatory"))
        }
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
        put(
            "routing",
            buildRouting(
                routingMode = routingModeOverride ?: settings?.routingMode ?: "global",
                domainStrategy = settings?.domainStrategy ?: "AsIs",
                customDomains = settings?.customDomains.orEmpty(),
                customIps = settings?.customIps.orEmpty(),
                enableLocalDns = settings?.enableLocalDns != false,
                includeTun = includeTun,
                iranCidrs = iranCidrs,
                blockQuic = settings?.blockQuic == true,
            ),
        )
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
            put(
                "routeOnly",
                sniffingEnabled && ((settings?.routeOnly ?: false) || settings?.routingMode == "bypassIran"),
            )
        }
        if (includeTun) {
            put(JSONObject().apply {
                put("tag", "tun-in")
                put("port", 0)
                put("protocol", "tun")
                put("settings", JSONObject().apply {
                    // Xray 26.8+ probes net.Interfaces() when name is absent.
                    // Android supplies an already-established VpnService FD,
                    // so retain the explicit legacy name and let TUNGETIFF read
                    // the real Android interface name from that FD at runtime.
                    put("name", ANDROID_TUN_CONFIG_NAME)
                    put("mtu", settings?.vpnMtu ?: 1500)
                })
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
        put("protocol", if (server.protocol.equals("hysteria2", true)) "hysteria" else server.protocol.lowercase())
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
            "shadowsocks" -> JSONObject().apply {
                put("servers", JSONArray().put(JSONObject().apply {
                    put("address", server.address)
                    put("port", server.port)
                    put("method", server.parameters.getValue("method"))
                    put("password", server.credential)
                }))
            }
            "socks", "http" -> JSONObject().apply {
                put("servers", JSONArray().put(JSONObject().apply {
                    put("address", server.address)
                    put("port", server.port)
                    server.parameters["username"]?.takeIf(String::isNotBlank)?.let { username ->
                        put("users", JSONArray().put(JSONObject().apply {
                            put("user", username)
                            put("pass", server.credential)
                        }))
                    }
                }))
            }
            "hysteria2" -> JSONObject().apply {
                put("version", 2)
                put("address", server.address)
                put("port", server.port)
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
                // Current Xray has a first-class WebSocket Host field. The
                // legacy headers.Host form is only migrated for compatibility
                // and is not reliable with newer browser-forwarder paths.
                server.parameters["host"]?.takeIf(String::isNotBlank)?.let { put("host", it) }
            })
            "grpc" -> put("grpcSettings", JSONObject().apply {
                put("serviceName", server.parameters["serviceName"] ?: server.parameters["path"] ?: "")
                put("multiMode", server.parameters["mode"].equals("multi", true))
            })
            "xhttp" -> put("xhttpSettings", JSONObject().apply {
                put("path", server.parameters["path"] ?: "/")
                server.parameters["host"]?.takeIf(String::isNotBlank)?.let { put("host", it) }
                server.parameters["mode"]?.takeIf(String::isNotBlank)?.let { put("mode", it) }
                server.parameters["extra"]?.trim()?.takeIf(String::isNotEmpty)?.let { raw ->
                    put("extra", runCatching { JSONObject(raw) }
                        .getOrElse { throw IllegalArgumentException("XHTTP extra must be a JSON object", it) })
                }
            })
            "tcp" -> server.parameters["headerType"]?.takeIf { it != "none" && it.isNotBlank() }?.let { headerType ->
                put("tcpSettings", JSONObject().apply {
                    put("header", JSONObject().apply { put("type", headerType) })
                })
            }
            "hysteria" -> put("hysteriaSettings", JSONObject().apply {
                put("version", 2)
                put("auth", server.credential)
            })
        }
        when (server.security.lowercase()) {
            "tls" -> put("tlsSettings", JSONObject().apply {
                put("serverName", tlsServerName(server))
                putOptionalArray("alpn", server.parameters["alpn"])
                server.parameters["fp"]?.takeIf(String::isNotBlank)?.let { put("fingerprint", it) }
                server.parameters["cs"]?.trim()?.takeIf(String::isNotBlank)?.let { put("cipherSuites", it) }
                server.parameters["pcs"]?.trim()?.takeIf(String::isNotBlank)?.let {
                    putOptionalArray("pinnedPeerCertSha256", it)
                }
                server.parameters["vcn"]?.takeIf { it == "1" || it.equals("true", true) }?.let {
                    put("verifyPeerCertByName", true)
                }
            })
            "reality" -> put("realitySettings", JSONObject().apply {
                require(!server.parameters["fp"].equals("unsafe", true)) {
                    "Fingerprint unsafe is supported only by TLS transports"
                }
                put("serverName", server.parameters["sni"] ?: server.address)
                put("fingerprint", server.parameters["fp"] ?: "chrome")
                put("publicKey", server.parameters["pbk"] ?: "")
                put("shortId", server.parameters["sid"] ?: "")
                put("spiderX", server.parameters["spx"] ?: "/")
                (server.parameters["mldsa65Verify"] ?: server.parameters["pqv"])
                    ?.takeIf(String::isNotBlank)
                    ?.let { put("mldsa65Verify", it) }
            })
        }
        val profileFinalMask = server.parameters["fm"]?.trim()?.takeIf(String::isNotEmpty)
        if (profileFinalMask != null) {
            val decoded = runCatching { JSONObject(profileFinalMask) }
                .getOrElse { throw IllegalArgumentException("FinalMask must be a JSON object", it) }
            put("finalmask", decoded)
        } else if (server.protocol.equals("hysteria2", true) && server.parameters["obfs"].equals("salamander", true)) {
            put("finalmask", JSONObject().put("udp", JSONArray().put(JSONObject().apply {
                put("type", "salamander")
                put("settings", JSONObject().put("password", server.parameters.getValue("obfs-password")))
            })))
        } else if (settings?.fragmentEnabled == true && server.security.equals("tls", true) && network != "hysteria") {
            put("finalmask", buildFragment(settings))
        }
        if (settings?.enableIpv6 == true && settings.preferIpv6) {
            put(
                "sockopt",
                JSONObject().apply { put("domainStrategy", "UseIPv6v4") },
            )
        }
    }

    private fun buildFragment(settings: NativeSettings): JSONObject = buildFragmentSettings(
        packets = settings.fragmentPackets,
        length = settings.fragmentLength,
        interval = settings.fragmentInterval,
        maxSplit = settings.fragmentMaxSplit,
    )

    internal fun buildFragmentSettings(
        packets: String,
        length: String,
        interval: String,
        maxSplit: Int,
    ): JSONObject = JSONObject().apply {
        put("tcp", JSONArray().put(JSONObject().apply {
            put("type", "fragment")
            put("settings", JSONObject().apply {
                put("packets", packets)
                put("length", length)
                // Xray FinalMask calls the UI interval field `delay`.
                put("delay", interval)
                put("maxSplit", maxSplit)
            })
        }))
    }

    private fun tlsServerName(server: ServerRecord): String {
        val explicit = server.parameters["sni"]?.trim().orEmpty()
        if (explicit.isNotEmpty()) return explicit
        return server.parameters["host"]?.split(',')?.firstOrNull()?.trim()
            ?.takeIf(String::isNotEmpty) ?: server.address
    }

    private fun buildDns(settings: NativeSettings?): JSONObject = buildDnsSettings(
        remoteDns = settings?.remoteDns ?: "localhost",
        directDnsEnabled = settings?.directDnsEnabled == true,
        directDns = settings?.directDns.orEmpty(),
        routingMode = settings?.routingMode ?: "global",
        customDomains = settings?.customDomains.orEmpty(),
        fakeDns = settings?.enableLocalDns == true && settings.enableFakeDns,
        enableIpv6 = settings?.enableIpv6 == true,
    )

    internal fun buildDnsSettings(
        remoteDns: String,
        directDnsEnabled: Boolean,
        directDns: String,
        routingMode: String,
        customDomains: String,
        fakeDns: Boolean,
        enableIpv6: Boolean,
    ): JSONObject = JSONObject().apply {
        val servers = remoteDns
            .let(::splitRules)
            .distinct()
            .ifEmpty { listOf("localhost") }
            .mapTo(mutableListOf<Any>()) { it }
        val directDomains = when (routingMode) {
            "bypassIran" -> listOf("domain:ir", "full:localhost", "domain:localhost", "domain:local")
            "custom" -> splitDomainRules(customDomains)
            else -> emptyList()
        }
        if (directDnsEnabled && directDns.isNotBlank() && directDomains.isNotEmpty()) {
            splitRules(directDns).asReversed().forEach { resolver ->
                servers.add(0, JSONObject().apply {
                    put("address", asDirectDnsAddress(resolver))
                    put("domains", JSONArray(directDomains))
                    put("skipFallback", true)
                })
            }
        }
        if (fakeDns) servers.add(0, "fakedns")
        put("servers", JSONArray(servers))
        put("queryStrategy", if (enableIpv6) "UseIP" else "UseIPv4")
    }

    internal fun buildObservatorySections(
        leastPingInterval: String,
        leastLoadInterval: String,
        httpMethod: String,
        sampling: Int,
        timeout: String,
    ): JSONObject = JSONObject().apply {
        put("observatory", JSONObject().apply {
            put("subjectSelector", JSONArray().put("proxy"))
            put("probeURL", "https://www.google.com/generate_204")
            put("probeInterval", leastPingInterval)
            put("enableConcurrency", false)
        })
        put("burstObservatory", JSONObject().apply {
            put("subjectSelector", JSONArray().put("proxy"))
            put("pingConfig", JSONObject().apply {
                put("destination", "https://www.google.com/generate_204")
                put("connectivity", "")
                put("interval", leastLoadInterval)
                put("httpMethod", httpMethod)
                put("sampling", sampling)
                put("timeout", timeout)
            })
        })
    }

    internal fun buildRouting(
        routingMode: String,
        domainStrategy: String = "AsIs",
        customDomains: String = "",
        customIps: String = "",
        enableLocalDns: Boolean = true,
        includeTun: Boolean = true,
        iranCidrs: List<String> = emptyList(),
        blockQuic: Boolean = false,
    ): JSONObject = JSONObject().apply {
        require(routingMode in setOf("global", "bypassIran", "custom")) { "Unsupported routing mode" }
        require(domainStrategy in setOf("AsIs", "IPIfNonMatch", "IPOnDemand")) { "Unsupported domain strategy" }
        put("domainStrategy", domainStrategy)
        put("rules", JSONArray().apply {
            if (blockQuic) {
                put(JSONObject().apply {
                    put("type", "field")
                    put("network", "udp")
                    put("port", "443")
                    put("outboundTag", "blocked")
                })
            }
            if (enableLocalDns) {
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
            val privateDomains = listOf("full:localhost", "domain:localhost", "domain:local")
            val parsedCustomIps = splitRules(customIps)
            val parsedCustomDomains = splitDomainRules(customDomains)
            when (routingMode) {
                "bypassIran" -> {
                    require(iranCidrs.isNotEmpty()) { "Iran CIDR assets are unavailable" }
                    putRoutingRule(
                        "direct",
                        emptyList(),
                        listOf("domain:ir") + privateDomains,
                    )
                    putRoutingRule("direct", PRIVATE_IPS + iranCidrs, emptyList())
                }
                "custom" -> {
                    putRoutingRule("direct", PRIVATE_IPS, privateDomains)
                    putRoutingRule("direct", parsedCustomIps, parsedCustomDomains)
                }
            }
        })
    }

    fun validateGeneratedConfig(config: String) {
        val root = runCatching { JSONObject(config) }
            .getOrElse { throw IllegalArgumentException("Generated Xray JSON is invalid", it) }
        val outbounds = root.optJSONArray("outbounds") ?: error("Generated Xray config has no outbounds")
        root.optJSONArray("inbounds")?.let { inbounds ->
            for (index in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(index) ?: continue
                if (!inbound.optString("protocol").equals("tun", true)) continue
                require(
                    inbound.optJSONObject("settings")?.optString("name") == ANDROID_TUN_CONFIG_NAME,
                ) { "Generated Android TUN config must use an explicit interface name" }
            }
        }
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
                    require(!ip.startsWith("geoip:", true)) {
                        "Generated Xray IP rule requires unavailable geoip data"
                    }
                }
            }
        }
    }

    private fun validateServer(server: ServerRecord) {
        require(server.protocol.lowercase() in setOf("vless", "vmess", "trojan", "shadowsocks", "socks", "http", "hysteria2")) { "Unsupported proxy protocol" }
        require(server.address.isNotBlank() && server.address.length <= 253) { "Server address is invalid" }
        require(server.port in 1..65_535) { "Server port is invalid" }
        if (server.protocol.lowercase() !in setOf("socks", "http")) require(server.credential.isNotBlank()) { "Server credential is missing" }
        require(server.security.lowercase() in setOf("", "none", "tls", "reality")) { "Unsupported transport security" }
        if (server.protocol.equals("shadowsocks", true)) require(!server.parameters["method"].isNullOrBlank()) { "Shadowsocks method is missing" }
        if (server.protocol.equals("hysteria2", true)) require(server.parameters["version"] == "2") { "Only Hysteria2 is supported" }
        if (server.security.equals("reality", true)) {
            require(!server.parameters["pbk"].isNullOrBlank()) { "Reality public key is missing" }
        }
    }

    private fun asDirectDnsAddress(value: String): String = when {
        value.startsWith("https://", true) -> "https+local://${value.substringAfter("://")}"
        value.startsWith("tcp://", true) -> "tcp+local://${value.substringAfter("://")}"
        value.startsWith("quic://", true) -> "quic+local://${value.substringAfter("://")}"
        value.contains("://") -> value
        value.contains(':') -> "tcp+local://[$value]"
        else -> "tcp+local://$value"
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

    private fun splitDomainRules(value: String): List<String> = value
        .lineSequence()
        .flatMap { line ->
            val trimmed = line.trim()
            if (trimmed.startsWith("regexp:", true)) sequenceOf(trimmed)
            else trimmed.split(',').asSequence()
        }
        .map(String::trim)
        .filter(String::isNotEmpty)
        .toList()

    private fun JSONObject.putOptionalArray(key: String, csv: String?) {
        val values = csv?.split(',')?.map(String::trim)?.filter(String::isNotEmpty).orEmpty()
        if (values.isNotEmpty()) put(key, JSONArray(values))
    }

    private val PRIVATE_IPS = listOf(
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "::1/128",
        "fc00::/7",
        "fe80::/10",
    )
}

package dev.nirang.client.settings

import android.content.Context
import android.net.Uri
import dev.nirang.client.BuildConfig
import java.net.Inet6Address
import java.net.InetAddress

class NativeSettings(context: Context) {
    private val prefs = context.getSharedPreferences("nirang_settings", Context.MODE_PRIVATE)

    init {
        migrateInstallDefaults()
    }

    val connectionMode: String get() = safeString("connectionMode", "vpn").takeIf(ALLOWED_CONNECTION_MODES::contains) ?: "vpn"
    val routingMode: String get() = when (safeString("routingMode", FRESH_INSTALL_DEFAULTS.routingMode)) {
        "bypassIran" -> "bypassIran"
        "custom" -> "custom"
        else -> "global"
    }
    val customDomains: String get() = safeString("customDomains", "").takeIf(::validDomainRules) ?: ""
    val customIps: String get() = safeString("customIps", "").takeIf(::validIpRules) ?: ""
    val enableLocalDns: Boolean get() = safeBoolean("enableLocalDns", true)
    val enableFakeDns: Boolean get() = safeBoolean("enableFakeDns", false)
    val remoteDns: String get() = safeString("remoteDns", DEFAULT_REMOTE_DNS).takeIf(::validDnsResolvers) ?: DEFAULT_REMOTE_DNS
    val vpnDns: String get() = safeString("vpnDns", DEFAULT_VPN_DNS).takeIf(::validIpAddress) ?: DEFAULT_VPN_DNS
    val vpnInterfaceAddress: String get() = safeString("vpnInterfaceAddress", DEFAULT_VPN_ADDRESS).takeIf(::validVpnAddress) ?: DEFAULT_VPN_ADDRESS
    val localSocksPort: Int get() = safeInt("localSocksPort", 10808).takeIf { it in 1024..65_535 } ?: 10808
    val realPingConcurrency: Int get() = safeInt("realPingConcurrency", 16).takeIf(ALLOWED_PING_CONCURRENCY::contains) ?: 16
    val domainStrategy: String get() = safeString("domainStrategy", "AsIs").takeIf(ALLOWED_DOMAIN_STRATEGIES::contains) ?: "AsIs"
    val sniffingEnabled: Boolean get() = safeBoolean("sniffingEnabled", true)
    val routeOnly: Boolean get() = safeBoolean("routeOnly", false)
    val fragmentEnabled: Boolean get() = safeBoolean("fragmentEnabled", false)
    val fragmentPackets: String get() = safeString("fragmentPackets", "tlshello").takeIf(::validFragmentPackets) ?: "tlshello"
    val fragmentLength: String get() = safeString("fragmentLength", "50-100").takeIf { validRange(it, 1, 65_535) } ?: "50-100"
    val fragmentInterval: String get() = safeString("fragmentInterval", "10-20").takeIf { validRange(it, 1, 10_000) } ?: "10-20"
    val fragmentMaxSplit: Int get() = safeInt("fragmentMaxSplit", 10).takeIf { it in 0..10_000 } ?: 10
    val enableIpv6: Boolean get() = safeBoolean("enableIpv6", FRESH_INSTALL_DEFAULTS.enableIpv6)
    val preferIpv6: Boolean get() = safeBoolean("preferIpv6", false)
    val vpnMtu: Int get() = safeInt("vpnMtu", 1500).takeIf { it in 1280..9000 } ?: 1500
    val autoUpdate: Boolean get() = safeBoolean("autoUpdate", true)
    val updateIntervalHours: Int get() = safeInt("updateIntervalHours", 12).takeIf(ALLOWED_INTERVALS::contains) ?: 12
    val themeMode: String get() = safeString("themeMode", "system").takeIf(ALLOWED_THEMES::contains) ?: "system"
    val language: String get() = safeString("language", "en").takeIf(ALLOWED_LANGUAGES::contains) ?: "en"
    val performanceMode: Boolean get() = safeBoolean("performanceMode", false)
    val performanceModePrompted: Boolean get() = safeBoolean("performanceModePrompted", false)
    val ipCheckUrl: String get() = safeString("ipCheckUrl", DEFAULT_IP_CHECK).takeIf(::validHttpsUrl) ?: DEFAULT_IP_CHECK

    fun toMap(): Map<String, Any?> = mapOf(
        "connectionMode" to connectionMode,
        "routingMode" to routingMode,
        "customDomains" to customDomains,
        "customIps" to customIps,
        "enableLocalDns" to enableLocalDns,
        "enableFakeDns" to enableFakeDns,
        "remoteDns" to remoteDns,
        "vpnDns" to vpnDns,
        "vpnInterfaceAddress" to vpnInterfaceAddress,
        "localSocksPort" to localSocksPort,
        "realPingConcurrency" to realPingConcurrency,
        "domainStrategy" to domainStrategy,
        "sniffingEnabled" to sniffingEnabled,
        "routeOnly" to routeOnly,
        "fragmentEnabled" to fragmentEnabled,
        "fragmentPackets" to fragmentPackets,
        "fragmentLength" to fragmentLength,
        "fragmentInterval" to fragmentInterval,
        "fragmentMaxSplit" to fragmentMaxSplit,
        "enableIpv6" to enableIpv6,
        "preferIpv6" to preferIpv6,
        "vpnMtu" to vpnMtu,
        "autoUpdate" to autoUpdate,
        "updateIntervalHours" to updateIntervalHours,
        "themeMode" to themeMode,
        "language" to language,
        "performanceMode" to performanceMode,
        "performanceModePrompted" to performanceModePrompted,
        "ipCheckUrl" to ipCheckUrl,
        "telegramUrlConfigured" to BuildConfig.TELEGRAM_URL.isNotBlank(),
        "telegramContact" to BuildConfig.TELEGRAM_CONTACT,
    )

    fun update(values: Map<*, *>) {
        val strings = mutableMapOf<String, String>()
        values["connectionMode"]?.toString()?.let {
            require(it in ALLOWED_CONNECTION_MODES) { "Unsupported connection mode" }
            strings["connectionMode"] = it
        }
        values["routingMode"]?.toString()?.let {
            require(it in ALLOWED_ROUTING) { "Unsupported routing mode" }
            strings["routingMode"] = it
        }
        values["customDomains"]?.toString()?.let {
            require(validDomainRules(it)) { "Custom domain rules are invalid or too large" }
            strings["customDomains"] = it.trim()
        }
        values["customIps"]?.toString()?.let {
            require(validIpRules(it)) { "Custom IP rules are invalid or too large" }
            strings["customIps"] = it.trim()
        }
        values["remoteDns"]?.toString()?.trim()?.let {
            require(validDnsResolvers(it)) { "Remote DNS resolvers are invalid" }
            strings["remoteDns"] = it
        }
        values["vpnDns"]?.toString()?.trim()?.let {
            require(validIpAddress(it)) { "VPN DNS must be an IPv4 or IPv6 address" }
            strings["vpnDns"] = it
        }
        values["vpnInterfaceAddress"]?.toString()?.trim()?.let {
            require(validVpnAddress(it)) { "VPN interface address must be a private IPv4 CIDR" }
            strings["vpnInterfaceAddress"] = it
        }
        values["domainStrategy"]?.toString()?.let {
            require(it in ALLOWED_DOMAIN_STRATEGIES) { "Unsupported domain strategy" }
            strings["domainStrategy"] = it
        }
        values["fragmentPackets"]?.toString()?.trim()?.lowercase()?.let {
            require(validFragmentPackets(it)) { "Fragment packets must be tlshello or 1-1 through 1-5" }
            strings["fragmentPackets"] = it
        }
        values["fragmentLength"]?.toString()?.trim()?.let {
            require(validRange(it, 1, 65_535)) { "Fragment length must be an ascending min-max range" }
            strings["fragmentLength"] = it
        }
        values["fragmentInterval"]?.toString()?.trim()?.let {
            require(validRange(it, 1, 10_000)) { "Fragment interval must be an ascending min-max range" }
            strings["fragmentInterval"] = it
        }

        val booleans = mutableMapOf<String, Boolean>()
        for (key in BOOLEAN_KEYS) {
            if (!values.containsKey(key)) continue
            val value = values[key]
            require(value is Boolean) { "$key value is invalid" }
            booleans[key] = value
        }
        val mtu = (values["vpnMtu"] as? Number)?.toInt()
        if (values.containsKey("vpnMtu")) {
            require(mtu != null && mtu in 1280..9000) { "VPN MTU must be between 1280 and 9000" }
        }
        val socksPort = (values["localSocksPort"] as? Number)?.toInt()
        if (values.containsKey("localSocksPort")) {
            require(socksPort != null && socksPort in 1024..65_535 && socksPort != 10809) {
                "Local SOCKS port must be between 1024 and 65535 and cannot use 10809"
            }
        }
        val pingConcurrency = (values["realPingConcurrency"] as? Number)?.toInt()
        if (values.containsKey("realPingConcurrency")) {
            require(pingConcurrency in ALLOWED_PING_CONCURRENCY) { "Unsupported real-delay concurrency" }
        }
        val fragmentMaxSplitValue = (values["fragmentMaxSplit"] as? Number)?.toInt()
        if (values.containsKey("fragmentMaxSplit")) {
            require(fragmentMaxSplitValue != null && fragmentMaxSplitValue in 0..10_000) {
                "Fragment max split must be between 0 and 10000"
            }
        }
        values["themeMode"]?.toString()?.let {
            require(it in ALLOWED_THEMES) { "Unsupported theme mode" }
            strings["themeMode"] = it
        }
        values["language"]?.toString()?.let {
            require(it in ALLOWED_LANGUAGES) { "Unsupported language" }
            strings["language"] = it
        }
        values["ipCheckUrl"]?.toString()?.trim()?.let {
            require(validHttpsUrl(it)) { "Public IP provider must be a valid HTTPS URL" }
            strings["ipCheckUrl"] = it
        }

        val autoUpdateValue = values["autoUpdate"]
        if (values.containsKey("autoUpdate")) {
            require(autoUpdateValue is Boolean) { "Auto-update value is invalid" }
        }
        val interval = (values["updateIntervalHours"] as? Number)?.toInt()
        if (values.containsKey("updateIntervalHours")) {
            require(interval in ALLOWED_INTERVALS) { "Unsupported update interval" }
        }

        val editor = prefs.edit()
        strings.forEach { (key, value) -> editor.putString(key, value) }
        booleans.forEach { (key, value) -> editor.putBoolean(key, value) }
        mtu?.let { editor.putInt("vpnMtu", it) }
        socksPort?.let { editor.putInt("localSocksPort", it) }
        pingConcurrency?.let { editor.putInt("realPingConcurrency", it) }
        fragmentMaxSplitValue?.let { editor.putInt("fragmentMaxSplit", it) }
        (autoUpdateValue as? Boolean)?.let { editor.putBoolean("autoUpdate", it) }
        interval?.let { editor.putInt("updateIntervalHours", it) }
        editor.apply()
    }

    fun resetNetworkToSafeDefaults() {
        prefs.edit()
            .putString("routingMode", "global")
            .putString("domainStrategy", "AsIs")
            .putBoolean("sniffingEnabled", true)
            .putBoolean("routeOnly", false)
            .apply()
    }

    fun incrementOpenCount() {
        prefs.edit().putInt("openCount", safeInt("openCount", 0).coerceAtLeast(0) + 1).apply()
    }

    fun telegramReminderEligible(): Boolean {
        if (BuildConfig.TELEGRAM_URL.isBlank()) return false
        if (safeBoolean("telegramNever", false)) return false
        if (safeInt("openCount", 0) < 3) return false
        val lastShown = safeLong("telegramLastShown", 0L)
        return System.currentTimeMillis() - lastShown >= 7L * 24L * 60L * 60L * 1000L
    }

    fun recordTelegramDecision(decision: String) {
        val editor = prefs.edit().putLong("telegramLastShown", System.currentTimeMillis())
        if (decision == "never") editor.putBoolean("telegramNever", true)
        editor.apply()
    }

    private fun migrateInstallDefaults() = synchronized(DEFAULTS_MIGRATION_LOCK) {
        val schemaVersion = runCatching { prefs.getInt(DEFAULTS_SCHEMA_KEY, 0) }.getOrDefault(0)
        if (schemaVersion >= DEFAULTS_SCHEMA_VERSION) return@synchronized

        val defaults = InstallDefaults.forExistingState(prefs.all.isNotEmpty())
        val editor = prefs.edit()
        if (!prefs.contains("routingMode")) editor.putString("routingMode", defaults.routingMode)
        if (!prefs.contains("domainStrategy")) editor.putString("domainStrategy", defaults.domainStrategy)
        if (!prefs.contains("enableIpv6")) editor.putBoolean("enableIpv6", defaults.enableIpv6)
        editor.putInt(DEFAULTS_SCHEMA_KEY, DEFAULTS_SCHEMA_VERSION).commit()
    }

    private fun safeString(key: String, fallback: String): String = safePreference(key, fallback) { prefs.getString(key, fallback) ?: fallback }
    private fun safeBoolean(key: String, fallback: Boolean): Boolean = safePreference(key, fallback) { prefs.getBoolean(key, fallback) }
    private fun safeInt(key: String, fallback: Int): Int = safePreference(key, fallback) { prefs.getInt(key, fallback) }
    private fun safeLong(key: String, fallback: Long): Long = safePreference(key, fallback) { prefs.getLong(key, fallback) }

    private inline fun <T> safePreference(key: String, fallback: T, read: () -> T): T = runCatching(read).getOrElse {
        prefs.edit().remove(key).apply()
        fallback
    }

    companion object {
        private const val DEFAULTS_SCHEMA_KEY = "installDefaultsSchema"
        private const val DEFAULTS_SCHEMA_VERSION = 1
        private val DEFAULTS_MIGRATION_LOCK = Any()
        private val FRESH_INSTALL_DEFAULTS = InstallDefaults.forExistingState(false)
        private const val DEFAULT_REMOTE_DNS = "https://dns.google/dns-query"
        private const val DEFAULT_VPN_DNS = "1.1.1.1"
        private const val DEFAULT_VPN_ADDRESS = "10.10.14.1/30"
        private const val DEFAULT_IP_CHECK = "https://api.ip.sb/geoip"
        private val ALLOWED_CONNECTION_MODES = setOf("vpn", "proxy")
        private val ALLOWED_ROUTING = setOf("global", "bypassIran", "custom")
        private val ALLOWED_DOMAIN_STRATEGIES = setOf("AsIs", "IPIfNonMatch", "IPOnDemand")
        private val ALLOWED_INTERVALS = setOf(6, 12, 24)
        private val ALLOWED_PING_CONCURRENCY = setOf(4, 8, 16, 32)
        private val ALLOWED_THEMES = setOf("system", "light", "dark")
        private val ALLOWED_LANGUAGES = setOf("en", "fa")
        private val BOOLEAN_KEYS = setOf(
            "enableLocalDns",
            "enableFakeDns",
            "sniffingEnabled",
            "routeOnly",
            "fragmentEnabled",
            "enableIpv6",
            "preferIpv6",
            "performanceMode",
            "performanceModePrompted",
        )
        private val HOSTNAME = Regex("^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
        private val IPV4 = Regex("^(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)(?:\\.(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)){3}$")

        private fun validIpAddress(value: String): Boolean {
            if (value.isBlank() || value.length > 253 || value.any(Char::isWhitespace)) return false
            val isIpv6 = value.contains(':') && runCatching { InetAddress.getByName(value) is Inet6Address }.getOrDefault(false)
            return IPV4.matches(value) || isIpv6
        }

        private fun validDnsResolvers(value: String): Boolean {
            val resolvers = splitRules(value)
            if (resolvers.isEmpty() || resolvers.size > 8) return false
            return resolvers.all { resolver ->
                if (resolver.length > 2048 || resolver.any(Char::isWhitespace)) return@all false
                if (validIpAddress(resolver) || HOSTNAME.matches(resolver)) return@all true
                val uri = runCatching { Uri.parse(resolver) }.getOrNull() ?: return@all false
                uri.scheme?.lowercase() in setOf("https", "https+local", "quic+local", "tcp", "tcp+local") &&
                    !uri.host.isNullOrBlank()
            }
        }

        private fun validVpnAddress(value: String): Boolean {
            val parts = value.split('/', limit = 2)
            if (parts.size != 2 || !IPV4.matches(parts[0])) return false
            val prefix = parts[1].toIntOrNull() ?: return false
            if (prefix !in 16..30) return false
            val first = parts[0].substringBefore('.').toIntOrNull() ?: return false
            val second = parts[0].substringAfter('.').substringBefore('.').toIntOrNull() ?: return false
            return first == 10 || (first == 172 && second in 16..31) || (first == 192 && second == 168)
        }

        private fun validHttpsUrl(value: String): Boolean = runCatching {
            val uri = Uri.parse(value)
            uri.scheme.equals("https", true) && !uri.host.isNullOrBlank() && value.length <= 2048
        }.getOrDefault(false)

        private fun validRuleText(value: String): Boolean = value.length <= 16_384 && value.none { it == '\u0000' || (it.isISOControl() && it !in "\n\r\t") }

        private fun validDomainRules(value: String): Boolean {
            if (!validRuleText(value)) return false
            return splitDomainRules(value).all { rule ->
                if (rule.length > 512) return@all false
                when {
                    rule.startsWith("regexp:", true) -> rule.substringAfter(':').isNotBlank()
                    rule.any(Char::isWhitespace) -> false
                    rule.startsWith("domain:", true) || rule.startsWith("full:", true) ->
                        HOSTNAME.matches(rule.substringAfter(':'))
                    else -> HOSTNAME.matches(rule)
                }
            }
        }

        private fun validIpRules(value: String): Boolean {
            if (!validRuleText(value)) return false
            return splitRules(value).all { rule ->
                validIpOrCidr(rule)
            }
        }

        private fun validIpOrCidr(rule: String): Boolean {
            val parts = rule.split('/', limit = 2)
            val address = parts[0]
            val ipv4 = IPV4.matches(address)
            val ipv6 = address.contains(':') && runCatching {
                InetAddress.getByName(address) is Inet6Address
            }.getOrDefault(false)
            if (!ipv4 && !ipv6) return false
            if (parts.size == 1) return true
            val prefix = parts[1].toIntOrNull() ?: return false
            return prefix in 0..if (ipv4) 32 else 128
        }

        private fun validFragmentPackets(value: String): Boolean =
            value.lowercase() in setOf("tlshello", "1-1", "1-2", "1-3", "1-4", "1-5")

        private fun validRange(value: String, minimum: Int, maximum: Int): Boolean {
            val parts = value.split('-', limit = 2)
            if (parts.size != 2) return false
            val from = parts[0].trim().toIntOrNull() ?: return false
            val to = parts[1].trim().toIntOrNull() ?: return false
            return from in minimum..maximum && to in minimum..maximum && from <= to
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
    }
}

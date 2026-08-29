package dev.nirang.client.vpn

object RestartPolicy {
    private val restartRequiredKeys = setOf(
        "connectionMode",
        "routingMode",
        "customDomains",
        "customIps",
        "domainStrategy",
        "enableIpv6",
        "preferIpv6",
        "enableFakeDns",
        "enableLocalDns",
        "remoteDns",
        "vpnDns",
        "vpnMtu",
        "vpnInterfaceAddress",
        "sniffingEnabled",
        "routeOnly",
        "fragmentEnabled",
        "fragmentPackets",
        "fragmentLength",
        "fragmentInterval",
        "fragmentMaxSplit",
        "localSocksPort",
    )

    fun requiresRestart(changedKeys: Set<String>): Boolean =
        changedKeys.any(restartRequiredKeys::contains)
}

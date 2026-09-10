package dev.nirang.client.settings

internal data class InstallDefaults(
    val routingMode: String,
    val domainStrategy: String,
    val enableIpv6: Boolean,
    val directDnsEnabled: Boolean,
    val directDns: String,
    val routeOnly: Boolean,
    val blockQuic: Boolean,
    val muxEnabled: Boolean,
) {
    companion object {
        fun forExistingState(existingInstall: Boolean): InstallDefaults = if (existingInstall) {
            InstallDefaults(
                routingMode = "global",
                domainStrategy = "AsIs",
                enableIpv6 = false,
                directDnsEnabled = false,
                directDns = "",
                routeOnly = false,
                blockQuic = false,
                muxEnabled = false,
            )
        } else {
            InstallDefaults(
                routingMode = "bypassIran",
                domainStrategy = "AsIs",
                enableIpv6 = true,
                directDnsEnabled = true,
                directDns = "178.22.122.100",
                routeOnly = true,
                blockQuic = false,
                muxEnabled = false,
            )
        }
    }
}

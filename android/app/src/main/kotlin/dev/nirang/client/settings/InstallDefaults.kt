package dev.nirang.client.settings

internal data class InstallDefaults(
    val routingMode: String,
    val domainStrategy: String,
    val enableIpv6: Boolean,
) {
    companion object {
        fun forExistingState(existingInstall: Boolean): InstallDefaults = if (existingInstall) {
            InstallDefaults(
                routingMode = "global",
                domainStrategy = "AsIs",
                enableIpv6 = false,
            )
        } else {
            InstallDefaults(
                routingMode = "bypassIran",
                domainStrategy = "AsIs",
                enableIpv6 = true,
            )
        }
    }
}

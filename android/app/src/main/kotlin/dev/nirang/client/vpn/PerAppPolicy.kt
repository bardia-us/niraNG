package dev.nirang.client.vpn

internal data class PerAppRules(
    val allowed: Set<String> = emptySet(),
    val disallowed: Set<String> = emptySet(),
    val fellBackToAllApps: Boolean = false,
)

/** Pure policy calculation kept separate from VpnService.Builder for regression tests. */
internal object PerAppPolicy {
    fun resolve(
        mode: String,
        configuredPackages: Set<String>,
        installedPackages: Set<String>,
        ownPackage: String,
    ): PerAppRules {
        val usable = configuredPackages
            .asSequence()
            .filter { it != ownPackage && it in installedPackages }
            .toSet()
        return when (mode) {
            "selected" -> if (usable.isEmpty()) {
                PerAppRules(disallowed = setOf(ownPackage), fellBackToAllApps = true)
            } else {
                PerAppRules(allowed = usable)
            }
            "exclude" -> PerAppRules(disallowed = usable + ownPackage)
            else -> PerAppRules(disallowed = setOf(ownPackage))
        }
    }
}

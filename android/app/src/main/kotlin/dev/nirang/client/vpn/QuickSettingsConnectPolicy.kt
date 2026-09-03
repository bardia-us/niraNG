package dev.nirang.client.vpn

internal enum class QuickSettingsConnectAction {
    CONNECT_DIRECTLY,
    OPEN_APP_FOR_PREREQUISITES,
}

/** Keeps a fresh-install tile tap out of VpnService until every Android/app prerequisite exists. */
internal object QuickSettingsConnectPolicy {
    fun action(
        hasServer: Boolean,
        hasRegistrationConsent: Boolean,
        hasVpnPermission: Boolean,
        hasNotificationPermission: Boolean,
    ): QuickSettingsConnectAction = if (
        hasServer && hasRegistrationConsent && hasVpnPermission && hasNotificationPermission
    ) {
        QuickSettingsConnectAction.CONNECT_DIRECTLY
    } else {
        QuickSettingsConnectAction.OPEN_APP_FOR_PREREQUISITES
    }
}

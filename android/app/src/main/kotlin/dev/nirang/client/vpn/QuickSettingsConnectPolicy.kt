package dev.nirang.client.vpn

internal enum class QuickSettingsConnectAction {
    CONNECT_DIRECTLY,
    OPEN_APP_FOR_PREREQUISITES,
}

/** Notification visibility is optional; app and VPN consent are mandatory. */
internal object QuickSettingsConnectPolicy {
    fun action(
        hasServer: Boolean,
        hasRegistrationConsent: Boolean,
        hasVpnPermission: Boolean,
        @Suppress("UNUSED_PARAMETER") hasNotificationPermission: Boolean,
    ): QuickSettingsConnectAction = if (
        hasServer && hasRegistrationConsent && hasVpnPermission
    ) {
        QuickSettingsConnectAction.CONNECT_DIRECTLY
    } else {
        QuickSettingsConnectAction.OPEN_APP_FOR_PREREQUISITES
    }
}

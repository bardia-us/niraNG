package dev.nirang.client.vpn

import dev.nirang.client.model.ConnectionState
import org.junit.Assert.assertEquals
import org.junit.Test

class QuickSettingsTilePolicyTest {
    @Test
    fun `fresh install tile connect opens prerequisite flow instead of starting service`() {
        assertEquals(
            QuickSettingsConnectAction.OPEN_APP_FOR_PREREQUISITES,
            QuickSettingsConnectPolicy.action(
                hasServer = true,
                hasRegistrationConsent = true,
                hasVpnPermission = false,
                hasNotificationPermission = false,
            ),
        )
    }

    @Test
    fun `tile connects directly only after every prerequisite is ready`() {
        assertEquals(
            QuickSettingsConnectAction.CONNECT_DIRECTLY,
            QuickSettingsConnectPolicy.action(true, true, true, true),
        )
        assertEquals(
            QuickSettingsTilePresentation.CONNECTING,
            QuickSettingsTilePolicy.presentation(ConnectionState.PREPARING),
        )
        assertEquals(
            QuickSettingsTilePresentation.CONNECTED,
            QuickSettingsTilePolicy.presentation(ConnectionState.CONNECTED),
        )
    }

    @Test
    fun `terminal states project to active and inactive`() {
        assertEquals(
            QuickSettingsTilePresentation.CONNECTED,
            QuickSettingsTilePolicy.presentation(ConnectionState.CONNECTED),
        )
        assertEquals(
            QuickSettingsTilePresentation.DISCONNECTED,
            QuickSettingsTilePolicy.presentation(ConnectionState.DISCONNECTED),
        )
        assertEquals(
            QuickSettingsTilePresentation.DISCONNECTED,
            QuickSettingsTilePolicy.presentation(ConnectionState.ERROR),
        )
    }

    @Test
    fun `connection transients stay connecting only until a terminal state`() {
        listOf(
            ConnectionState.PREPARING,
            ConnectionState.CONNECTING,
            ConnectionState.RESTARTING,
            ConnectionState.SWITCHING,
            ConnectionState.RECONNECTING,
        ).forEach { state ->
            assertEquals(
                QuickSettingsTilePresentation.CONNECTING,
                QuickSettingsTilePolicy.presentation(state),
            )
        }
        assertEquals(
            QuickSettingsTilePresentation.DISCONNECTING,
            QuickSettingsTilePolicy.presentation(ConnectionState.STOPPING),
        )
    }
}

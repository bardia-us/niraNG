package dev.nirang.client.vpn

import dev.nirang.client.model.ConnectionState
import org.junit.Assert.assertEquals
import org.junit.Test

class QuickSettingsTilePolicyTest {
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

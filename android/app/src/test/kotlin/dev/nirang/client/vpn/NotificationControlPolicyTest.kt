package dev.nirang.client.vpn

import dev.nirang.client.model.ConnectionState
import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationControlPolicyTest {
    @Test
    fun `only real connected state exposes disconnect`() {
        assertEquals(
            NotificationControlAction.DISCONNECT,
            NotificationControlPolicy.action(ConnectionState.CONNECTED),
        )
    }

    @Test
    fun `disconnected and error states allow a new connect`() {
        assertEquals(
            NotificationControlAction.CONNECT,
            NotificationControlPolicy.action(ConnectionState.DISCONNECTED),
        )
        assertEquals(
            NotificationControlAction.CONNECT,
            NotificationControlPolicy.action(ConnectionState.ERROR),
        )
    }

    @Test
    fun `transitional states reject duplicate taps`() {
        val transitional = listOf(
            ConnectionState.PREPARING,
            ConnectionState.CONNECTING,
            ConnectionState.RESTARTING,
            ConnectionState.SWITCHING,
            ConnectionState.RECONNECTING,
            ConnectionState.STOPPING,
        )
        transitional.forEach {
            assertEquals(NotificationControlAction.NONE, NotificationControlPolicy.action(it))
        }
    }
}

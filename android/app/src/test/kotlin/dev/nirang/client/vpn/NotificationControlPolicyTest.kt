package dev.nirang.client.vpn

import dev.nirang.client.model.ConnectionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationControlPolicyTest {
    @Test
    fun `terminal state cannot repost an ongoing notification before teardown finishes`() {
        listOf(ConnectionState.DISCONNECTED, ConnectionState.ERROR).forEach { state ->
            assertFalse(NotificationControlPolicy.shouldUpdateNotification(true, state, state))
        }
    }

    @Test
    fun `queued connected snapshot cannot resurrect notification after disconnect`() {
        assertFalse(NotificationControlPolicy.shouldUpdateNotification(
            true, ConnectionState.CONNECTED, ConnectionState.DISCONNECTED,
        ))
        assertFalse(NotificationControlPolicy.shouldUpdateNotification(
            false, ConnectionState.CONNECTED, ConnectionState.CONNECTED,
        ))
        assertTrue(NotificationControlPolicy.shouldUpdateNotification(
            true, ConnectionState.CONNECTED, ConnectionState.CONNECTED,
        ))
    }

    @Test
    fun `launcher badge exists only while VPN is really connected`() {
        ConnectionState.entries.forEach { state ->
            assertEquals(
                if (state == ConnectionState.CONNECTED) 1 else 0,
                NotificationControlPolicy.badgeCount(state),
            )
        }
    }

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

package dev.nirang.client.vpn

import dev.nirang.client.model.ConnectionState

internal enum class NotificationControlAction { CONNECT, DISCONNECT, NONE }

/** Pure projection of the real service state; no notification-owned state. */
internal object NotificationControlPolicy {
    fun badgeCount(state: ConnectionState): Int = if (state == ConnectionState.CONNECTED) 1 else 0

    fun action(state: ConnectionState): NotificationControlAction = when (state) {
        ConnectionState.CONNECTED -> NotificationControlAction.DISCONNECT
        ConnectionState.DISCONNECTED,
        ConnectionState.ERROR -> NotificationControlAction.CONNECT
        ConnectionState.PREPARING,
        ConnectionState.CONNECTING,
        ConnectionState.RESTARTING,
        ConnectionState.SWITCHING,
        ConnectionState.RECONNECTING,
        ConnectionState.STOPPING -> NotificationControlAction.NONE
    }
}

package dev.nirang.client.vpn

import dev.nirang.client.model.ConnectionState

internal enum class QuickSettingsTilePresentation {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    DISCONNECTING,
}

/** Pure projection of ConnectionStore; the tile never owns or guesses VPN state. */
internal object QuickSettingsTilePolicy {
    fun presentation(state: ConnectionState): QuickSettingsTilePresentation = when (state) {
        ConnectionState.CONNECTED -> QuickSettingsTilePresentation.CONNECTED
        ConnectionState.STOPPING -> QuickSettingsTilePresentation.DISCONNECTING
        ConnectionState.PREPARING,
        ConnectionState.CONNECTING,
        ConnectionState.RESTARTING,
        ConnectionState.SWITCHING,
        ConnectionState.RECONNECTING -> QuickSettingsTilePresentation.CONNECTING
        ConnectionState.DISCONNECTED,
        ConnectionState.ERROR -> QuickSettingsTilePresentation.DISCONNECTED
    }
}

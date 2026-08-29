package dev.nirang.client.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import dev.nirang.client.MainActivity
import dev.nirang.client.R
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.registration.DeviceRegistrationManager
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.SubscriptionRepository

/** User-added Quick Settings control backed by the same VPN service as Flutter. */
class NirangTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        render(ConnectionStore.state())
    }

    override fun onClick() {
        super.onClick()
        when (ConnectionStore.state()) {
            ConnectionState.CONNECTED,
            ConnectionState.PREPARING,
            ConnectionState.CONNECTING,
            ConnectionState.RESTARTING,
            ConnectionState.SWITCHING,
            ConnectionState.RECONNECTING,
            ConnectionState.STOPPING -> {
                render(ConnectionState.STOPPING)
                NirangVpnService.stop(applicationContext)
            }

            ConnectionState.DISCONNECTED,
            ConnectionState.ERROR -> connectOrOpenApp()
        }
    }

    private fun connectOrOpenApp() {
        val server = SubscriptionRepository(applicationContext).selectedServer()
        val settings = NativeSettings(applicationContext)
        val hasVpnPermission = settings.connectionMode == "proxy" || VpnService.prepare(this) == null
        if (
            server == null ||
            !DeviceRegistrationManager.hasConsent(this) ||
            !hasVpnPermission
        ) {
            openApp()
            return
        }
        render(ConnectionState.CONNECTING)
        runCatching { NirangVpnService.start(applicationContext, server.id) }
            .onFailure {
                ConnectionStore.transition(
                    ConnectionState.ERROR,
                    server.id,
                    server.name,
                    getString(R.string.operation_failed_native),
                )
                render(ConnectionState.ERROR)
            }
    }

    @Suppress("DEPRECATION")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivityAndCollapse(intent)
    }

    private fun render(state: ConnectionState) {
        val tile = qsTile ?: return
        val connected = state == ConnectionState.CONNECTED
        val busy = state in setOf(
            ConnectionState.PREPARING,
            ConnectionState.CONNECTING,
            ConnectionState.RESTARTING,
            ConnectionState.SWITCHING,
            ConnectionState.RECONNECTING,
            ConnectionState.STOPPING,
        )
        tile.state = when {
            connected -> Tile.STATE_ACTIVE
            busy -> Tile.STATE_UNAVAILABLE
            else -> Tile.STATE_INACTIVE
        }
        tile.label = getString(R.string.quick_tile_label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(
                when {
                    connected -> R.string.quick_tile_connected
                    busy -> R.string.quick_tile_connecting
                    else -> R.string.quick_tile_disconnected
                },
            )
        }
        tile.updateTile()
    }
}

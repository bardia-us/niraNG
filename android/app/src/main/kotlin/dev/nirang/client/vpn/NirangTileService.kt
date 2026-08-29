package dev.nirang.client.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
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
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectionListener: (ConnectionSnapshot) -> Unit = { snapshot ->
        mainHandler.post { render(snapshot) }
    }

    override fun onStartListening() {
        super.onStartListening()
        ConnectionStore.addListener(connectionListener)
    }

    override fun onStopListening() {
        ConnectionStore.removeListener(connectionListener)
        super.onStopListening()
    }

    override fun onDestroy() {
        ConnectionStore.removeListener(connectionListener)
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        when (NotificationControlPolicy.action(ConnectionStore.state())) {
            NotificationControlAction.DISCONNECT -> {
                NirangVpnService.stop(applicationContext)
            }
            NotificationControlAction.CONNECT -> connectOrOpenApp()
            NotificationControlAction.NONE -> Unit
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
        runCatching { NirangVpnService.start(applicationContext, server.id) }
            .onFailure {
                ConnectionStore.transition(
                    ConnectionState.ERROR,
                    server.id,
                    server.name,
                    getString(R.string.operation_failed_native),
                )
            }
    }

    @Suppress("DEPRECATION")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivityAndCollapse(intent)
    }

    private fun render(snapshot: ConnectionSnapshot) {
        val tile = qsTile ?: return
        val state = snapshot.state
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

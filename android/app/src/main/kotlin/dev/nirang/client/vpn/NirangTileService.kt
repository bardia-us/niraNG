package dev.nirang.client.vpn

import android.Manifest
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
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
        val hasVpnPermission = settings.connectionMode == "proxy" ||
            runCatching { VpnService.prepare(this) == null }.getOrDefault(false)
        val hasNotificationPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (QuickSettingsConnectPolicy.action(
                hasServer = server != null,
                hasRegistrationConsent = DeviceRegistrationManager.hasConsent(this),
                hasVpnPermission = hasVpnPermission,
                hasNotificationPermission = hasNotificationPermission,
            ) == QuickSettingsConnectAction.OPEN_APP_FOR_PREREQUISITES
        ) {
            openApp()
            return
        }
        val selectedServer = server ?: return
        DeviceRegistrationManager.runIfAllowed(
            applicationContext,
            onAllowed = { NirangVpnService.start(applicationContext, selectedServer.id) },
            onDenied = {
                ConnectionStore.transition(
                    ConnectionState.ERROR,
                    selectedServer.id,
                    selectedServer.name,
                    getString(R.string.operation_failed_native),
                )
            },
        )
    }

    @Suppress("DEPRECATION")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_CONNECT_FROM_TILE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    TILE_CONNECT_REQUEST_CODE,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                startActivityAndCollapse(pendingIntent)
            } else {
                startActivityAndCollapse(intent)
            }
        }.onFailure {
            ConnectionStore.transition(ConnectionState.ERROR, message = getString(R.string.operation_failed_native))
            requestRefresh(applicationContext)
        }
    }

    private fun render(snapshot: ConnectionSnapshot) {
        val tile = qsTile ?: return
        val presentation = QuickSettingsTilePolicy.presentation(snapshot.state)
        tile.state = when (presentation) {
            QuickSettingsTilePresentation.CONNECTED -> Tile.STATE_ACTIVE
            QuickSettingsTilePresentation.CONNECTING,
            QuickSettingsTilePresentation.DISCONNECTING -> Tile.STATE_UNAVAILABLE
            QuickSettingsTilePresentation.DISCONNECTED -> Tile.STATE_INACTIVE
        }
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_nirang)
        tile.label = getString(R.string.quick_tile_label)
        val status = getString(
            when (presentation) {
                QuickSettingsTilePresentation.CONNECTED -> R.string.quick_tile_connected
                QuickSettingsTilePresentation.CONNECTING -> R.string.quick_tile_connecting
                QuickSettingsTilePresentation.DISCONNECTING -> R.string.quick_tile_disconnecting
                QuickSettingsTilePresentation.DISCONNECTED -> R.string.quick_tile_disconnected
            },
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = status
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = status
        }
        tile.updateTile()
    }

    companion object {
        private const val TILE_CONNECT_REQUEST_CODE = 4211
        /** Ask Android to bind/listen again even when the Quick Settings panel is closed. */
        fun requestRefresh(context: Context) {
            runCatching {
                TileService.requestListeningState(
                    context.applicationContext,
                    ComponentName(context, NirangTileService::class.java),
                )
            }
        }
    }
}

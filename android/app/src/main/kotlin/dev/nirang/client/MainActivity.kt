package dev.nirang.client

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import dev.nirang.client.bridge.NirangBridge
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.registration.DeviceRegistrationManager
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.vpn.ConnectionStore
import dev.nirang.client.vpn.NirangVpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: NirangBridge? = null
    private var pendingServerId: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTileConnection = false

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureTileRequest(intent)
        continuePendingTileConnection()
    }

    override fun onPostResume() {
        super.onPostResume()
        captureTileRequest(intent)
        continuePendingTileConnection()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return
        val result = pendingResult
        val serverId = pendingServerId
        pendingResult = null
        pendingServerId = null
        if (resultCode == Activity.RESULT_OK && serverId != null) {
            if (startVpnSafely(serverId)) result?.success(true)
            else result?.error("service_start_failed", "Android could not start the VPN service", null)
        } else {
            ConnectionStore.transition(ConnectionState.ERROR, message = "VPN permission was denied")
            result?.error("permission_denied", "VPN permission was denied", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) continuePendingConnection()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = NirangBridge(this, flutterEngine, ::requestVpnPermission)
    }

    override fun onDestroy() {
        if (isFinishing) {
            pendingResult?.error("cancelled", "VPN permission request was cancelled", null)
            pendingResult = null
            pendingServerId = null
        }
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }

    private fun requestVpnPermission(serverId: String, result: MethodChannel.Result) {
        if (!DeviceRegistrationManager.hasConsent(this)) {
            result.error("consent_required", "Device registration consent is required", null)
            return
        }
        if (pendingResult != null) {
            result.error("busy", "A VPN permission request is already active", null)
            return
        }
        pendingServerId = serverId
        pendingResult = result
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            runCatching {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
            }.onFailure { failPendingConnection("Notification permission could not be requested", it) }
            return
        }
        continuePendingConnection()
    }

    private fun continuePendingConnection() {
        val serverId = pendingServerId ?: return
        val result = pendingResult ?: return
        if (NativeSettings(this).connectionMode == "proxy") {
            pendingServerId = null
            pendingResult = null
            if (startVpnSafely(serverId)) result.success(true)
            else result.error("service_start_failed", "Android could not start the proxy service", null)
            return
        }
        val intent: Intent? = VpnService.prepare(this)
        if (intent == null) {
            pendingServerId = null
            pendingResult = null
            if (startVpnSafely(serverId)) result.success(true)
            else result.error("service_start_failed", "Android could not start the VPN service", null)
            return
        }
        runCatching { startActivityForResult(intent, VPN_PERMISSION_REQUEST) }
            .onFailure { failPendingConnection("VPN permission could not be requested", it) }
    }

    private fun startVpnSafely(serverId: String): Boolean = runCatching {
        NirangVpnService.start(this, serverId)
    }.onFailure { error ->
        SafeLog.error(this, "VPN service launch failed: ${error.javaClass.simpleName}")
        ConnectionStore.transition(ConnectionState.ERROR, serverId, message = "Android could not start the VPN service")
    }.isSuccess

    private fun failPendingConnection(message: String, error: Throwable) {
        val result = pendingResult
        pendingResult = null
        val serverId = pendingServerId
        pendingServerId = null
        SafeLog.error(this, "$message: ${error.javaClass.simpleName}")
        ConnectionStore.transition(ConnectionState.ERROR, serverId, message = message)
        result?.error("permission_request_failed", message, null)
    }

    /** Called again after consent/startup/subscription becomes ready. */
    fun continuePendingTileConnection() {
        if (!pendingTileConnection || pendingResult != null) return
        if (bridge?.connectFromTileIfReady() == true) pendingTileConnection = false
    }

    private fun captureTileRequest(source: Intent?) {
        if (source?.action != ACTION_CONNECT_FROM_TILE) return
        pendingTileConnection = true
        source.action = null
    }

    companion object {
        const val ACTION_CONNECT_FROM_TILE = "dev.nirang.client.action.CONNECT_FROM_TILE"
        private const val VPN_PERMISSION_REQUEST = 4108
        private const val NOTIFICATION_PERMISSION_REQUEST = 4109
    }
}

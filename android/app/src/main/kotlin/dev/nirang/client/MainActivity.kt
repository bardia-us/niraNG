package dev.nirang.client

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import dev.nirang.client.bridge.NirangBridge
import dev.nirang.client.model.ConnectionState
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return
        val result = pendingResult
        val serverId = pendingServerId
        pendingResult = null
        pendingServerId = null
        if (resultCode == Activity.RESULT_OK && serverId != null) {
            NirangVpnService.start(this, serverId)
            result?.success(true)
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
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
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
            NirangVpnService.start(this, serverId)
            result.success(true)
            return
        }
        val intent: Intent? = VpnService.prepare(this)
        if (intent == null) {
            pendingServerId = null
            pendingResult = null
            NirangVpnService.start(this, serverId)
            result.success(true)
            return
        }
        startActivityForResult(intent, VPN_PERMISSION_REQUEST)
    }

    companion object {
        private const val VPN_PERMISSION_REQUEST = 4108
        private const val NOTIFICATION_PERMISSION_REQUEST = 4109
    }
}

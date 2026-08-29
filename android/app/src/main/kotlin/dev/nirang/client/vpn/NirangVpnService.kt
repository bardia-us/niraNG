package dev.nirang.client.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import dev.nirang.client.MainActivity
import dev.nirang.client.R
import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.model.ServerEligibility
import dev.nirang.client.network.ProxyIpChecker
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.SubscriptionRepository
import dev.nirang.client.xray.XrayConfigBuilder
import dev.nirang.client.xray.XrayCore
import dev.nirang.client.xray.IranCidrRepository
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

class NirangVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    private val coreStopWorker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nirang-core-stop").apply { isDaemon = true }
    }
    private val startGuard = AtomicBoolean(false)
    private val operationGate = ConnectionOperationGate()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var currentConfig: String? = null
    private var currentServerId: String? = null
    private var currentServerName: String? = null
    private var currentMode: String = "vpn"
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var activeNetwork: Network? = null
    @Volatile private var networkWasLost = false

    override fun onCreate() {
        super.onCreate()
        SafeLog.initialize(this)
        ensureNotificationChannel()
        if (
            !XrayCore.isRunning() &&
            ConnectionStore.state() !in setOf(ConnectionState.DISCONNECTED, ConnectionState.RESTARTING, ConnectionState.ERROR)
        ) {
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        runCatching {
        when (intent?.action) {
            ACTION_STOP -> stopImmediately(false)
            ACTION_STOP_PRESERVING_ERROR -> stopImmediately(true)
            ACTION_STOP_FOR_RESTART -> {
                val generation = intent.getLongExtra(EXTRA_RESTART_GENERATION, 0L)
                val serverId = intent.getStringExtra(EXTRA_SERVER_ID)
                val serverName = intent.getStringExtra(EXTRA_SERVER_NAME)
                submit { stopForRestartInternal(generation, serverId, serverName) }
            }
            ACTION_START -> {
                val operation = operationGate.begin()
                startForeground(NOTIFICATION_ID, buildNotification(getString(R.string.vpn_connecting), null))
                val serverId = intent.getStringExtra(EXTRA_SERVER_ID)
                val allowFallback = intent.getBooleanExtra(EXTRA_ALLOW_FALLBACK, true)
                submit { startInternal(serverId, allowFallback, operation) }
            }
            ACTION_SWITCH -> intent.getStringExtra(EXTRA_SERVER_ID)?.let {
                VpnRestartCoordinator.request(applicationContext, it)
            }
        }
        }.onFailure(::handleLifecycleFailure)
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        SafeLog.warning(this, "VPN permission revoked")
        stopImmediately(false)
    }

    override fun onDestroy() {
        operationGate.cancel()
        closeTunnelAndCallbacks()
        stopCoreAsync()
        if (ConnectionStore.state() !in setOf(ConnectionState.DISCONNECTED, ConnectionState.RESTARTING, ConnectionState.ERROR)) {
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
        }
        worker.shutdownNow()
        coreStopWorker.shutdown()
        super.onDestroy()
    }

    private fun startInternal(requestedServerId: String?, allowFallback: Boolean, operation: Long) {
        if (!startGuard.compareAndSet(false, true)) return
        if (!operationGate.isCurrent(operation)) {
            startGuard.set(false)
            return
        }
        if (ConnectionStore.state() in setOf(ConnectionState.CONNECTING, ConnectionState.CONNECTED, ConnectionState.SWITCHING, ConnectionState.RECONNECTING)) {
            startGuard.set(false)
            return
        }
        val repository = SubscriptionRepository(this)
        val server = requestedServerId?.let(repository::server) ?: repository.selectedServer()
        if (server == null) {
            failAndStop("No server is available")
            return
        }
        ServerEligibility.rejectionReason(server)?.let { reason ->
            failAndStop(reason)
            return
        }
        repository.select(server.id)
        currentServerId = server.id
        currentServerName = server.name
        ConnectionStore.transition(ConnectionState.PREPARING, server.id, server.name)
        SafeLog.info(this, "Server selected")
        val settings = NativeSettings(this)
        currentMode = settings.connectionMode

        try {
            val iranCidrs = routingCidrs(settings)
            if (currentMode == "vpn" && prepare(this) != null) error("VPN permission is not granted")
            currentConfig = if (currentMode == "vpn") {
                XrayConfigBuilder.buildVpnConfig(server, settings, iranCidrs)
            } else {
                XrayConfigBuilder.buildProxyConfig(server, settings, iranCidrs)
            }
            vpnInterface = if (currentMode == "vpn") {
                buildVpnInterface(server.name, settings) ?: error("Android could not establish the VPN interface")
            } else {
                null
            }
            check(operationGate.isCurrent(operation)) { CANCELLED_OPERATION }
            ConnectionStore.transition(ConnectionState.CONNECTING, server.id, server.name)
            updateNotification(getString(R.string.vpn_connecting), server.name)
            XrayCore.start(this, currentConfig!!, vpnInterface?.fd ?: 0)
            if (!operationGate.isCurrent(operation)) {
                cleanupResources()
                return
            }
            registerNetworkCallback()
            ConnectionStore.transition(ConnectionState.CONNECTED, server.id, server.name)
            markLastWorking(server.id)
            updateNotification(getString(R.string.vpn_connected), server.name)
            SafeLog.info(this, "VPN started")
            SafeLog.info(this, "Xray started")
            submit { refreshPublicIp(settings.ipCheckUrl, server.id) }
        } catch (error: Throwable) {
            if (!operationGate.isCurrent(operation) || error.message == CANCELLED_OPERATION) {
                cleanupResources()
                return
            }
            if (allowFallback && tryStartLastWorkingServer(settings, repository, operation)) return
            failAndStop(error.message ?: "Connection failed")
            return
        } finally {
            startGuard.set(false)
        }
    }

    private fun tryStartLastWorkingServer(
        settings: NativeSettings,
        repository: SubscriptionRepository,
        operation: Long,
    ): Boolean {
        if (!operationGate.isCurrent(operation)) return false
        val fallbackId = runCatching {
            getSharedPreferences(VPN_STATE_PREFS, MODE_PRIVATE).getString(LAST_WORKING_SERVER_ID, null)
        }.getOrNull() ?: return false
        val fallback = repository.server(fallbackId) ?: return false
        val fd = vpnInterface?.fd ?: if (currentMode == "proxy") 0 else return false
        return runCatching {
            XrayCore.stop()
            check(operationGate.isCurrent(operation)) { CANCELLED_OPERATION }
            val fallbackConfig = if (currentMode == "vpn") {
                XrayConfigBuilder.buildSafeFallbackConfig(fallback)
            } else {
                XrayConfigBuilder.buildProxyConfig(fallback, settings, routingCidrs(settings))
            }
            ConnectionStore.transition(ConnectionState.CONNECTING, fallback.id, fallback.name)
            XrayCore.start(this, fallbackConfig, fd)
            if (!operationGate.isCurrent(operation)) {
                XrayCore.stop()
                return@runCatching false
            }
            currentServerId = fallback.id
            currentServerName = fallback.name
            currentConfig = fallbackConfig
            repository.select(fallback.id)
            NativeEvents.emit("servers", repository.safeServers())
            NativeSettings(this).also { safeSettings ->
                safeSettings.resetNetworkToSafeDefaults()
                NativeEvents.emit("settings", safeSettings.toMap())
            }
            registerNetworkCallback()
            ConnectionStore.transition(
                ConnectionState.CONNECTED,
                fallback.id,
                fallback.name,
                "Selected configuration failed; safe network settings restored",
            )
            updateNotification(getString(R.string.vpn_connected), fallback.name)
            SafeLog.warning(this, "Previous working server restored")
            submit { refreshPublicIp(settings.ipCheckUrl, fallback.id) }
            true
        }.getOrElse { false }
    }

    private fun markLastWorking(serverId: String) {
        getSharedPreferences(VPN_STATE_PREFS, MODE_PRIVATE)
            .edit().putString(LAST_WORKING_SERVER_ID, serverId).apply()
    }

    private fun buildVpnInterface(serverName: String, settings: NativeSettings): ParcelFileDescriptor? {
        val addressParts = settings.vpnInterfaceAddress.split('/', limit = 2)
        val interfaceAddress = addressParts[0]
        val interfacePrefix = addressParts[1].toInt()
        val builder = Builder()
            .setSession("niraNG · $serverName")
            .setMtu(settings.vpnMtu)
            .addAddress(interfaceAddress, interfacePrefix)
            .addRoute("0.0.0.0", 0)
            .addDisallowedApplication(packageName)
            .setBlocking(true)
        if (settings.enableIpv6) {
            builder
                .addAddress("fdfe:dcba:9877::1", 126)
                .addRoute("::", 0)
        }
        resolveVpnDns(settings)?.let { builder.addDnsServer(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        return builder.establish()
    }

    private fun resolveVpnDns(settings: NativeSettings): InetAddress? {
        runCatching { return InetAddress.getByName(settings.vpnDns) }
        val manager = getSystemService(ConnectivityManager::class.java)
        val systemDns = manager?.activeNetwork?.let { manager.getLinkProperties(it) }?.dnsServers?.firstOrNull()
        return systemDns ?: runCatching { InetAddress.getByName("1.1.1.1") }.getOrNull()
    }

    private fun registerNetworkCallback() {
        unregisterNetworkCallback()
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        connectivityManager = manager
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                activeNetwork = network
                runCatching { setUnderlyingNetworks(arrayOf(network)) }
                if (networkWasLost && ConnectionStore.state() == ConnectionState.RECONNECTING) {
                    networkWasLost = false
                    submit { reconnectCore() }
                }
            }

            override fun onLost(network: Network) {
                if (network != activeNetwork || ConnectionStore.state() != ConnectionState.CONNECTED) return
                networkWasLost = true
                ConnectionStore.transition(ConnectionState.RECONNECTING, currentServerId, currentServerName)
                updateNotification("Reconnecting", currentServerName)
                SafeLog.info(this@NirangVpnService, "Network changed")
            }
        }.also(manager::registerDefaultNetworkCallback)
    }

    private fun reconnectCore() {
        val operation = operationGate.begin()
        val config = currentConfig ?: return
        val fd = vpnInterface?.fd ?: if (currentMode == "proxy") 0 else return
        val delays = longArrayOf(500L, 1_500L, 3_000L)
        for (delay in delays) {
            if (!operationGate.isCurrent(operation)) return
            try {
                XrayCore.stop()
                Thread.sleep(delay)
                if (!operationGate.isCurrent(operation)) return
                XrayCore.start(this, config, fd)
                if (!operationGate.isCurrent(operation)) {
                    XrayCore.stop()
                    return
                }
                ConnectionStore.transition(ConnectionState.CONNECTED, currentServerId, currentServerName)
                updateNotification(getString(R.string.vpn_connected), currentServerName)
                SafeLog.info(this, "VPN reconnected")
                submit {
                    currentServerId?.let { refreshPublicIp(NativeSettings(this).ipCheckUrl, it) }
                }
                return
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            } catch (_: Throwable) {
                // Continue with bounded exponential backoff.
            }
        }
        if (!operationGate.isCurrent(operation)) return
        failAndStop("Unable to reconnect after network change")
    }

    private fun refreshPublicIp(providerUrl: String, expectedServerId: String) {
        if (!ConnectionStore.beginPublicIpRefresh(expectedServerId)) return
        repeat(PUBLIC_IP_ATTEMPTS) { attempt ->
            if (currentServerId != expectedServerId || ConnectionStore.state() != ConnectionState.CONNECTED) return
            val result = runCatching { ProxyIpChecker.check(providerUrl) }.getOrNull()
            if (result?.ip?.isNotBlank() == true) {
                if (ConnectionStore.setPublicIp(expectedServerId, result.ip, result.countryCode, result.city)) {
                    SafeLog.info(this, "Public IP refreshed")
                }
                return
            }
            if (attempt + 1 < PUBLIC_IP_ATTEMPTS) Thread.sleep(PUBLIC_IP_RETRY_DELAY_MS)
        }
        ConnectionStore.setPublicIp(expectedServerId, null, null, null)
        SafeLog.warning(this, "Public IP check failed")
    }

    private fun routingCidrs(settings: NativeSettings): List<String> =
        if (settings.routingMode == "bypassIran") IranCidrRepository.load(applicationContext) else emptyList()

    private fun failAndStop(message: String) {
        if (ConnectionStore.state() == ConnectionState.DISCONNECTED) return
        val technicalMessage = message
            .replace(Regex("https?://\\S+", RegexOption.IGNORE_CASE), "endpoint")
            .replace(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"), "identifier")
            .replace(Regex("(?i)(password|credential|uuid|publicKey|shortId|id)\\s*[:=]\\s*[^,}\\s]+"), "$1=[redacted]")
            .replace(Regex("[A-Za-z0-9_+/-]{48,}={0,2}"), "[redacted value]")
            .take(1_200)
        SafeLog.error(this, "Connection error: $technicalMessage")
        ConnectionStore.transition(
            ConnectionState.ERROR,
            currentServerId,
            currentServerName,
            technicalMessage.take(240),
        )
        stopInternal(true)
        startGuard.set(false)
    }

    private fun submit(action: () -> Unit): Boolean = try {
        worker.execute {
            runCatching(action).onFailure { error ->
                handleUnexpectedWorkerFailure(error)
            }
        }
        true
    } catch (_: RejectedExecutionException) {
        // Android can deliver a late network callback while onDestroy is
        // shutting the executor down. Dropping that stale callback avoids a
        // process-level uncaught exception.
        SafeLog.warning(this, "Ignored a late VPN lifecycle callback")
        false
    }

    private fun handleUnexpectedWorkerFailure(error: Throwable) {
        val message = error.message ?: error.javaClass.simpleName
        SafeLog.error(this, "Unhandled VPN worker failure: ${error.javaClass.simpleName}")
        if (ConnectionStore.state() !in setOf(ConnectionState.DISCONNECTED, ConnectionState.ERROR)) {
            failAndStop(message)
        }
    }

    private fun handleLifecycleFailure(error: Throwable) {
        SafeLog.error(this, "VPN service lifecycle failure: ${error.javaClass.simpleName}")
        ConnectionStore.transition(ConnectionState.ERROR, currentServerId, currentServerName, "VPN service could not start")
        runCatching { cleanupResources() }
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
        stopSelf()
    }

    private fun stopInternal(preserveError: Boolean) {
        operationGate.cancel()
        if (!preserveError) ConnectionStore.transition(ConnectionState.STOPPING, currentServerId, currentServerName)
        cleanupResources()
        if (!preserveError) ConnectionStore.transition(ConnectionState.DISCONNECTED)
        SafeLog.info(this, "VPN stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopImmediately(preserveError: Boolean) {
        operationGate.cancel()
        VpnRestartCoordinator.cancel()
        startGuard.set(false)
        if (!preserveError) ConnectionStore.transition(ConnectionState.DISCONNECTED)
        closeTunnelAndCallbacks()
        currentConfig = null
        currentServerId = null
        currentServerName = null
        currentMode = "vpn"
        stopCoreAsync()
        SafeLog.info(this, "VPN stop requested")
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
        stopSelf()
    }

    private fun stopForRestartInternal(generation: Long, serverId: String?, serverName: String?) {
        cleanupResources()
        ConnectionStore.transition(ConnectionState.RESTARTING, serverId, serverName)
        SafeLog.info(this, "VPN service stopped for restart")
        stopForeground(STOP_FOREGROUND_REMOVE)
        VpnRestartCoordinator.onServiceStopped(generation)
        stopSelf()
    }

    private fun cleanupResources() {
        runCatching { XrayCore.stop() }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        currentConfig = null
        currentServerId = null
        currentServerName = null
        currentMode = "vpn"
        unregisterNetworkCallback()
    }

    private fun closeTunnelAndCallbacks() {
        val tunnel = vpnInterface
        vpnInterface = null
        runCatching { tunnel?.close() }
        unregisterNetworkCallback()
    }

    private fun stopCoreAsync() {
        runCatching {
            coreStopWorker.execute {
                runCatching { XrayCore.stop() }
                    .onFailure { SafeLog.warning(this, "Xray stop did not complete cleanly") }
            }
        }
    }

    private fun unregisterNetworkCallback() {
        networkCallback?.let { callback -> runCatching { connectivityManager?.unregisterNetworkCallback(callback) } }
        networkCallback = null
        connectivityManager = null
        activeNetwork = null
        networkWasLost = false
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(CHANNEL_ID, getString(R.string.vpn_channel_name), NotificationManager.IMPORTANCE_LOW).apply {
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun updateNotification(status: String, serverName: String?) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(status, serverName))
    }

    private fun buildNotification(status: String, serverName: String?): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this, 1, Intent(this, NirangVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_nirang)
            .setContentTitle("niraNG")
            .setContentText(listOfNotNull(status, serverName).joinToString(" · "))
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(0, getString(R.string.vpn_disconnect), stopIntent)
            .build()
    }

    companion object {
        const val ACTION_START = "dev.nirang.client.action.START_VPN"
        const val ACTION_STOP = "dev.nirang.client.action.STOP_VPN"
        const val ACTION_STOP_PRESERVING_ERROR = "dev.nirang.client.action.STOP_VPN_PRESERVING_ERROR"
        const val ACTION_STOP_FOR_RESTART = "dev.nirang.client.action.STOP_VPN_FOR_RESTART"
        const val ACTION_SWITCH = "dev.nirang.client.action.SWITCH_VPN"
        const val EXTRA_SERVER_ID = "serverId"
        const val EXTRA_SERVER_NAME = "serverName"
        const val EXTRA_RESTART_GENERATION = "restartGeneration"
        const val EXTRA_ALLOW_FALLBACK = "allowFallback"
        private const val CHANNEL_ID = "nirang_vpn"
        private const val NOTIFICATION_ID = 4107
        private const val VPN_STATE_PREFS = "nirang_vpn_state"
        private const val LAST_WORKING_SERVER_ID = "lastWorkingServerId"
        private const val PUBLIC_IP_ATTEMPTS = 3
        private const val PUBLIC_IP_RETRY_DELAY_MS = 700L
        private const val CANCELLED_OPERATION = "Connection operation was cancelled"

        fun start(context: Context, serverId: String, allowFallback: Boolean = true) {
            val intent = Intent(context, NirangVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_SERVER_ID, serverId)
                .putExtra(EXTRA_ALLOW_FALLBACK, allowFallback)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            VpnRestartCoordinator.cancel()
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
            runCatching {
                context.startService(Intent(context, NirangVpnService::class.java).setAction(ACTION_STOP))
            }.onFailure {
                SafeLog.warning(context, "VPN stop command could not be delivered")
            }
        }

        internal fun stopPreservingError(context: Context) {
            context.startService(
                Intent(context, NirangVpnService::class.java).setAction(ACTION_STOP_PRESERVING_ERROR),
            )
        }

        internal fun stopForRestart(
            context: Context,
            generation: Long,
            serverId: String,
            serverName: String,
        ) {
            context.startService(
                Intent(context, NirangVpnService::class.java)
                    .setAction(ACTION_STOP_FOR_RESTART)
                    .putExtra(EXTRA_RESTART_GENERATION, generation)
                    .putExtra(EXTRA_SERVER_ID, serverId)
                    .putExtra(EXTRA_SERVER_NAME, serverName),
            )
        }

        fun restart(context: Context, serverId: String): Boolean =
            VpnRestartCoordinator.request(context, serverId)

        fun switchServer(context: Context, serverId: String) {
            restart(context, serverId)
        }
    }
}
